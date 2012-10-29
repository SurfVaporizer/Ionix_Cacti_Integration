#############################################################################
#                                                                           #
# Radius Client module for Perl 5                                           #
#                                                                           #
# Written by Carl Declerck <carl@miskatonic.inbe.net>, (c)1997              #
# All Rights Reserved. See the Perl Artistic License for copying & usage    #
# policy.                                                                   #
#                                                                           #
# Modified by Olexander Kapitanenko <kapitan@portaone.com>,                 #
#             Andrew Zhilenko <andrew@portaone.com>, 2002-2010.             #
#             and the rest of PortaOne team.                                #
#                                                                           #
# See the file 'Changes' in the distrution archive.                         #
#                                                                           #
#############################################################################
# 	$Id: Radius.pm,v 1.49 2010/11/10 06:52:02 andrew Exp $

package Authen::Radius;

use strict;
use FileHandle;
use IO::Socket;
use IO::Select;
use Digest::MD5;
use Data::Dumper;
use Data::HexDump;

use vars qw($VERSION @ISA @EXPORT);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(ACCESS_REQUEST ACCESS_ACCEPT ACCESS_REJECT
			ACCOUNTING_REQUEST ACCOUNTING_RESPONSE ACCOUNTING_STATUS
			DISCONNECT_REQUEST DISCONNECT_ACCEPT DISCONNECT_REJECT
			COA_REQUEST COA_ACCEPT COA_REJECT COA_ACK COA_NAK);

$VERSION = '0.20';

my (%dict_id, %dict_name, %dict_val, %dict_vendor_id, %dict_vendor_name );
my ($request_id) = $$ & 0xff;	# probably better than starting from 0
my ($radius_error, $error_comment) = ('ENONE', '');
my $debug = 0;

use constant WIMAX_VENDOR => '24757';
use constant WIMAX_CONTINUATION_BIT => 0b10000000;
#
# we'll need to predefine these attr types so we can do simple password
# verification without having to load a dictionary
#

$dict_id{'not defined'}{1}{'type'} = 'string';	# set 'username' attr type to string
$dict_id{'not defined'}{2}{'type'} = 'string';	# set 'password' attr type to string
$dict_id{'not defined'}{4}{'type'} = 'ipaddr';	# set 'NAS-IP-Address' attr type to string

use constant ACCESS_REQUEST               => 1;
use constant ACCESS_ACCEPT                => 2;
use constant ACCESS_REJECT                => 3;
use constant ACCOUNTING_REQUEST           => 4;
use constant ACCOUNTING_RESPONSE          => 5;
use constant ACCOUNTING_STATUS            => 6;
use constant DISCONNECT_REQUEST           => 40;
use constant DISCONNECT_ACCEPT            => 41;
use constant DISCONNECT_REJECT            => 42; 
use constant COA_REQUEST                  => 43; 
use constant COA_ACCEPT                   => 44;
use constant COA_ACK                      => 44;
use constant COA_REJECT                   => 45; 
use constant COA_NAK                      => 45; 

my $HMAC_MD5_BLCKSZ = 64;
my $RFC3579_MSG_AUTH_ATTR_ID = 80;
my $RFC3579_MSG_AUTH_ATTR_LEN = 18;
my %SERVICES = ( 'radius' => 1812, 
				'radacct' => 1813,
				'radius-acct' => 1813 );

sub new {
	my $class = shift;
	my %h = @_;
	my ($host, $port, $service);
	my $self = {};

	bless $self, $class;

	$self->set_error;
	$debug = $h{'Debug'};
    
    if (!$h{'Host'} && !$h{'NodeList'}) {
	    return $self->set_error('ENOHOST');
    }

	$service = $h{'Service'} ? $h{'Service'} : 'radius';
	my $serv_port = getservbyname($service, 'udp');
	if (!$serv_port && !exists($SERVICES{$service})) {
		return $self->set_error('EBADSERV');
	} elsif (!$serv_port) {
		$serv_port = $SERVICES{$service};
	}

	($host, $port) = split(/:/, $h{'Host'});
	if (!$port) {
		$port = $serv_port;
	}

	$self->{'timeout'} = $h{'TimeOut'} ? $h{'TimeOut'} : 5;
	$self->{'localaddr'} = $h{'LocalAddr'};
	$self->{'secret'} = $h{'Secret'};
	$self->{'message_auth'}  = $h{'Rfc3579MessageAuth'};
	print STDERR "Using Radius server $host:$port\n" if $debug;
	my %io_sock_args = (
				Type => SOCK_DGRAM,
				Proto => 'udp',
				Timeout => $self->{'timeout'},
				LocalAddr => $self->{'localaddr'},
	);
	if ($h{'NodeList'}) {
		# contains resolved node list in text respresentation 
		$self->{'node_list_a'} = {}; 
		foreach my $node_a (@{$h{'NodeList'}}) {
			my ($n_host, $n_port) = split(/:/, $node_a);
			if (!$n_port) {
				$n_port = $serv_port;
			}
			my @hostinfo = gethostbyname($n_host);
			if (!scalar(@hostinfo)) {
				print STDERR "Can't resolve node hostname '$n_host': $! - skipping it!\n" if $debug;
				next;
			}
			print STDERR "Adding ".inet_ntoa($hostinfo[4]).':'.$n_port." to node list.\n" if $debug;
			# store splitted address to avoid additional parsing later
			$self->{'node_list_a'}->{inet_ntoa($hostinfo[4]).':'.$n_port} = 
                    [inet_ntoa($hostinfo[4]), $n_port];
		}
		if (!scalar(keys %{$self->{'node_list_a'}})) {
			return $self->set_error('ESOCKETFAIL', 'Empty node list.');
		}
		if ($host) {
			my @hostinfo = gethostbyname($host);
			if (scalar(@hostinfo)) {
				my $act_addr_a = inet_ntoa($hostinfo[4]).':'.$port;
				if (exists($self->{'node_list_a'}->{$act_addr_a})) {
					$self->{'node_addr_a'} = $act_addr_a; 
				} else {
					print STDERR "'$host' doesn't exist in node list - ignoring it!\n" if $debug;
				}
			} else {
				print STDERR "Can't resolve active node hostname '$host': $! - ignoring it!\n" if $debug;
			}
		}
	} else {
		my @hostinfo = gethostbyname($host);
		if (!scalar(@hostinfo)) {
			return $self->set_error('ESOCKETFAIL', "Can't resolve hostname '".$host."'.");
		}
		$self->{'node_addr_a'} = inet_ntoa($hostinfo[4]).':'.$port;
	}
	if ($host) {
		$io_sock_args{'PeerAddr'} = $host;
		$io_sock_args{'PeerPort'} = $port;
		$self->{'sock'} = IO::Socket::INET->new(%io_sock_args) 
			or return $self->set_error('ESOCKETFAIL', $@);
	}
	$self;
}

sub send_packet {
	my ($self, $type, $retransmit) = @_;
	my ($data);
	my $length = 20 + length($self->{'attributes'});

	if (!$retransmit) {
		$request_id = ($request_id + 1) & 0xff;
	}
	$self->set_error;    
	if ($type == ACCOUNTING_REQUEST || $type == DISCONNECT_REQUEST
		|| $type == COA_REQUEST) {
		$self->{'authenticator'} = "\0" x 16;
		$self->{'authenticator'} =
		$self->calc_authenticator($type, $request_id, $length)
	} else {
		$self->gen_authenticator unless defined $self->{'authenticator'};
	}

	if ($self->{'message_auth'} && ($type == ACCESS_REQUEST)) {
		$length += $RFC3579_MSG_AUTH_ATTR_LEN;
		$data = pack('C C n', $type, $request_id, $length)
				. $self->{'authenticator'}  
				. $self->{'attributes'}
				. pack('C C', $RFC3579_MSG_AUTH_ATTR_ID, $RFC3579_MSG_AUTH_ATTR_LEN) 
				. "\0" x ($RFC3579_MSG_AUTH_ATTR_LEN - 2);

		my $msg_authenticator = $self->hmac_md5($data, $self->{'secret'}); 
		$data = pack('C C n', $type, $request_id, $length) 
				. $self->{'authenticator'} 
				. $self->{'attributes'}
				. pack('C C', $RFC3579_MSG_AUTH_ATTR_ID, $RFC3579_MSG_AUTH_ATTR_LEN) 
				. $msg_authenticator;
		if ($debug) {
			print STDERR "RFC3579 Message-Authenticator: "._ascii_to_hex($msg_authenticator).
					" was added to request.\n";
		}
	} else {
		$data = pack('C C n', $type, $request_id, $length)
				. $self->{'authenticator'} . $self->{'attributes'};
	}

	if ($debug) {
		print STDERR "Sending request:\n";
		print STDERR HexDump($data);
	}
	my $res;
	if (!defined($self->{'node_list_a'})) {
		if ($debug) { print STDERR 'Sending request to: '.$self->{'node_addr_a'}."\n"; }
		$res = $self->{'sock'}->send($data) || $self->set_error('ESENDFAIL', $!);
	} else {
		if (!$retransmit && defined($self->{'sock'})) {
			if ($debug) { print STDERR 'Sending request to active node: '.$self->{'node_addr_a'}."\n"; }
			$res = $self->{'sock'}->send($data) || $self->set_error('ESENDFAIL', $!);
		} else {
			if ($debug) { print STDERR "ReSending request to all cluster nodes.\n"; }
			$self->{'sock'} = undef;
			$self->{'sock_list'} = [];
			my %io_sock_args = (
						Type => SOCK_DGRAM,
						Proto => 'udp',
						Timeout => $self->{'timeout'},
						LocalAddr => $self->{'localaddr'},
			);
			foreach my $node (keys %{$self->{'node_list_a'}}) {
				if ($debug) { print STDERR 'Sending request to: '.$node."\n"; }
				$io_sock_args{'PeerAddr'} = $self->{'node_list_a'}->{$node}->[0];
				$io_sock_args{'PeerPort'} = $self->{'node_list_a'}->{$node}->[1];
				my $new_sock = IO::Socket::INET->new(%io_sock_args) 
					or return $self->set_error('ESOCKETFAIL', $@);
				$res = $new_sock->send($data) || $self->set_error('ESENDFAIL', $!);
				if ($res) {
					push @{$self->{'sock_list'}}, $new_sock;
				}
				$res ||= $res;
			}
		}
	}
    return $res;
}

sub recv_packet {
	my ($self, $detect_bad_id) = @_;
	my ($data, $type, $id, $length, $auth, $sh, $resp_attributes);

	$self->set_error;

	if (defined($self->{'sock_list'}) && scalar(@{$self->{'sock_list'}})) {
		$sh = IO::Select->new(@{$self->{'sock_list'}}) or return $self->set_error('ESELECTFAIL');
	} elsif (defined($self->{'sock'})) {
		$sh = IO::Select->new($self->{'sock'}) or return $self->set_error('ESELECTFAIL');
	} else {
		return $self->set_error('ESELECTFAIL');
	}
	my $timeout = $self->{'timeout'};
	my @ready;
	my $from_addr_n;
	while ($timeout > 0){
		my $start_time = time();
		@ready = $sh->can_read($self->{'timeout'}) or return $self->set_error('ETIMEOUT', $!);
		my $end_time = time();
		$timeout -= $end_time - $start_time;
		$from_addr_n = $ready[0]->recv($data, 65536);
		if (defined($from_addr_n)) {
			last;
		}
		if (!defined($from_addr_n) && !defined($self->{'sock_list'})) {
			return $self->set_error('ERECVFAIL', $!);
		}elsif ($debug) {
			print STDERR "Received error/event from one peer:".$!."\n";
		}
	}

	if ($debug) { 
		print STDERR "Received response:\n"; 
		print STDERR HexDump($data);
	}

	if (defined($self->{'sock_list'})) {
		# the sending attempt was 'broadcast' to all cluster nodes
		# switcking to single active node
		$self->{'sock'} = $ready[0];
		$self->{'sock_list'} = undef;
		my ($node_port, $node_iaddr) = sockaddr_in($from_addr_n);
		$self->{'node_addr_a'} = inet_ntoa($node_iaddr).':'.$node_port;
		if ($debug) {  print STDERR "Registering new active peeer:".$self->{'node_addr_a'}."\n"; }
	}

	($type, $id, $length, $auth, $resp_attributes ) = unpack('C C n a16 a*', $data);
	if ($detect_bad_id && defined($id) && ($id != $request_id) ) {
		return $self->set_error('EBADID');
	}
	
	if ($auth ne $self->calc_authenticator($type, $id, $length, $resp_attributes)) {
		return $self->set_error('EBADAUTH');
	}
	# rewrtite  attributes only in case of valid response
	$self->{'attributes'} = $resp_attributes;
	my $rfc3579_msg_auth;
	foreach my $a ($self->get_attributes()) {
		if ($a->{Code} == $RFC3579_MSG_AUTH_ATTR_ID) {
			$rfc3579_msg_auth = $a->{Value};
			last;
		}
	}
	if (defined($rfc3579_msg_auth)) {
		$self->replace_attr_value($RFC3579_MSG_AUTH_ATTR_ID, 
				"\0" x ($RFC3579_MSG_AUTH_ATTR_LEN - 2));
		my $hmac_data = pack('C C n', $type, $id, $length) 
						. $self->{'authenticator'}
						. $self->{'attributes'};
		my $calc_hmac = $self->hmac_md5($hmac_data, $self->{'secret'});
		if ($calc_hmac ne $rfc3579_msg_auth) {
			if ($debug) {
				print STDERR "Received response with INVALID RFC3579 Message-Authenticator.\n";
				print STDERR 'Received   '._ascii_to_hex($rfc3579_msg_auth)."\n";
				print STDERR 'Calculated '._ascii_to_hex($calc_hmac)."\n";
			}
			return $self->set_error('EBADAUTH');
		} elsif ($debug) {
			print STDERR "Received response with VALID RFC3579 Message-Authenticator.\n";
		}
	}

	return $type;
}

sub check_pwd {
	my ($self, $name, $pwd, $nas) = @_;

	$nas = eval { $self->{'sock'}->sockhost() } unless defined($nas);
	$self->clear_attributes;
	$self->add_attributes (
		{ Name => 1, Value => $name, Type => 'string' },
		{ Name => 2, Value => $pwd, Type => 'string' },
		{ Name => 4, Value => $nas || '127.0.0.1', Type => 'ipaddr' }
	);

	$self->send_packet(ACCESS_REQUEST);
	my $rcv = $self->recv_packet();
	return (defined($rcv) and $rcv == ACCESS_ACCEPT);
}

sub clear_attributes {
	my ($self) = @_;

	$self->set_error;

	delete $self->{'attributes'};

	1;
}

sub get_attributes {
	my ($self) = @_;
	my ($vendor, $vendor_id, $id, $length, $value, $type, $rawvalue, @a);
	my ($attrs) = $self->{'attributes'};

	$self->set_error;
	my $vendor_specific = $dict_name{'Vendor-Specific'}{'id'};

	while (length($attrs)) {
		($id, $length, $attrs) = unpack('C C a*', $attrs);
		($rawvalue, $attrs) = unpack('a' . ($length - 2) . ' a*', $attrs);
		if ( defined($vendor_specific) and $id == $vendor_specific ) {
			($vendor_id, $id, $length, $rawvalue) = unpack('N C C a*', $rawvalue);
			$vendor = defined $dict_vendor_id{$vendor_id}{'name'} ? $dict_vendor_id{$vendor_id}{'name'} : $vendor_id;
		} else {
			$vendor = 'not defined';
		}
		$type = $dict_id{$vendor}{$id}{'type'} || '';
		$value = undef;
		if ($type eq "string") {
			if ($id == 2 && $vendor eq 'not defined' ) {
				$value = '<encrypted>';
			} else {
				$value = $rawvalue;
			}
		} elsif ($type eq "integer") {
			$value = unpack('N', $rawvalue);
			$value = $dict_val{$id}{$value}{'name'} if defined $dict_val{$id}{$value}{'name'};
		} elsif ($type eq "ipaddr") {
			$value = inet_ntoa($rawvalue);
		} elsif ($type eq "avpair") {
			$value = $rawvalue;
			$value =~ s/^.*=//;
		} elsif ($type eq 'sublist') {
			# never got a chance to test it, since it seems that Digest attributes only come from clients
			my ($subid, $subvalue, $sublength, @values);
			$value = ''; my $subrawvalue = $rawvalue;
			while (length($subrawvalue)) {
				($subid, $sublength, $subrawvalue) = unpack('C C a*', $subrawvalue);
				($subvalue, $subrawvalue) = unpack('a' . ($sublength - 2) . ' a*', $subrawvalue);
				my $subname = $dict_val{$id}->{$subid}->{'name'};
				push @values, "$subname = \"$subvalue\"";
			}
			$value = join("; ", @values);
		} elsif ($type ne '') {
			print STDERR "Unsupported type '$type' for attribute with id:'$id'.\n" if $debug;
		} else {
			print STDERR "Unknown type for attribute with id:'$id'. Check Radius dictionaries!\n" if $debug;
		}

		push (@a, {	'Name' => defined $dict_id{$vendor}{$id}{'name'} ? $dict_id{$vendor}{$id}{'name'} : $id,
					'Code' => $id,
					'Value' => $value,
					'RawValue' => $rawvalue,
					'Vendor' => $vendor }
		);
	}

	return @a;
}
# it used to be 
# $vendor = defined $a->{'Vendor'} ? 
#    ( defined $dict_vendor_name{ $a->{'Vendor'} }{'id'} ? $dict_vendor_name{ $a->{'Vendor'} }{'id'} : int($a->{'Vendor'}) ) 
#    : ( defined $dict_name{$a->{'Name'}}{'vendor'} 
#	? $dict_vendor_name{ $dict_name{$a->{'Name'}}{'vendor'} }{'id'} : 'not defined' );

sub vendorID ($) {
    my ($attr) = @_;
    if (defined $attr->{'Vendor'}) {
	return defined $dict_vendor_name{ $attr->{'Vendor'} }{'id'} ? $dict_vendor_name{ $attr->{'Vendor'} }{'id'} : int($attr->{'Vendor'});
    } else {
	# look up vendor by attribute name
	my $vendor_name = $dict_name{$attr->{'Name'}}{'vendor'};
	my $vendor_id = defined ($dict_vendor_name{$vendor_name}{'id'}) ?
	    $dict_vendor_name{$vendor_name}{'id'} : 'not defined';
	return $vendor_id;
    }
}

sub encodeValue ($$$$$) {
    my ($self, $vendor, $id, $type, $name, $value) = @_;

    my $new_value;
    $type = '' unless defined $type;
    if ($type eq "string") {
	$new_value = $value;
	if ($id == 2 && $vendor eq 'not defined' ) {
	    $self->gen_authenticator();
	    $new_value = $self->encrypt_pwd($value);
	}
	$new_value = substr($new_value, 0, 253);
                #       if ($vendor eq WIMAX_VENDOR) {
                            # add the "continuation" byte
                            # but no support for attribute spli for now
                #           $value = pack('C', 0). substr($value, 0, 246);
                #       }
    } elsif ($type eq "integer") {
	my $enc_value;
	if ( defined $dict_val{$id}{$value}{'id'} ) {
	    $enc_value = $dict_val{$id}{$value}{'id'};
	} else {
	    $enc_value = int($value);
	}
	$new_value = pack('N', $enc_value);
    } elsif ($type eq "byte") {
	$new_value = pack('C', $value);
    } elsif ($type eq "short") {
	$new_value = pack('S', $value);
    } elsif ($type eq "signed") {
	# there should be something else, since it is signed
	$new_value = pack('N', $value);
    } elsif ($type eq "ipaddr") {
	$new_value = inet_aton($value);
    } elsif ($type eq "avpair") {
	$new_value = $name.'='.$value;
	$new_value = substr($new_value, 0, 253);
# WiMAX
    } elsif ($type eq "combo-ip") {
	if ($value =~ m/^\d+\.\d+\.\d+.\d+/) {
	    # IPv4 address
	    $new_value = inet_aton($value);
	} else {
	    # currently unsupported, use IPv4
	    $new_value = inet_aton($value);
	}
    } elsif ($type eq "octets") {
	$new_value = '';
	foreach my $c (split('', $value)) {
	    $new_value .= pack('C',ord($c));
	}
    } elsif ($type eq 'tlv' and ref($value)) {
	$new_value = '';
	foreach my $sub_attr (sort { $a->{'TLV_ID'} <=> $b->{'TLV_ID'} } @{$value}) {
	    my $sub_attr_name = $sub_attr->{'Name'};
	    my $sub_attr_type = defined $sub_attr->{'Type'} ? $sub_attr->{'Type'} : $dict_name{$sub_attr_name}{'type'};
	    my $sub_attr_id = defined $dict_name{$sub_attr_name}{'id'} ? $dict_name{$sub_attr_name}{'id'} : int($sub_attr_name);
	    my $sub_value = $self->encodeValue($vendor, $sub_attr_id, $sub_attr_type, $sub_attr->{'Name'}, $sub_attr->{'Value'});

	    if (defined($sub_value)) {
		$new_value .= pack('C C', $sub_attr_id, length($sub_value)+2).$sub_value;
	    }
	}
    } elsif ($type eq 'sublist') {
	# Digest attributes look like:
	# Digest-Attributes                = 'Method = "REGISTER"'
	my $digest = $value;
	my @pairs;
	if (ref($digest)) {
	    next unless ref($digest) eq 'HASH';
	    foreach my $key (keys %{$digest}) {
		push @pairs, [ $key => $digest->{$key} ];
	    }
	} else {
                                # string
	    foreach my $z (split(/\"\; /, $digest)) {
		my ($subname, $subvalue) = split(/\s+=\s+\"/, $z, 2);
		$subvalue =~ s/\"$//;
		push @pairs, [ $subname => $subvalue ];
	    }
	}
	$new_value = '';
	foreach my $da (@pairs) {
	    my ($subname, $subvalue) = @{$da};
	    my $subid = $dict_val{$id}->{$subname}->{'id'};
	    next unless defined($subid);
	    $new_value .= pack('C C', $subid, length($subvalue) + 2) . $subvalue;
	}
    } else {
	return;
    }
    return $new_value;
}


sub add_attributes {
	my ($self, @attr) = @_;
	my ($a, $vendor, $id, $type, $value);
	my @a = ();
	$self->set_error;

	# scan for WiMAX TLV
	my %request_tlvs;
	for my $attr (@attr) {
	    my $attr_name = $attr->{'Name'};
	    $id = defined $dict_name{$attr_name}{'id'} ? $dict_name{$attr_name}{'id'} : int($attr_name);
	    $vendor = vendorID($attr);
	    if (exists($dict_name{$attr_name}{'tlv'})) {
		# this is a TLV attribute
		my $tlv = $dict_name{$attr_name}{'tlv'};
		# insert TLV type so we can order them by type inside of the container attribute
		$attr->{'TLV_ID'} = $id;

		unless (exists($request_tlvs{$tlv})) {
		    # this is a first attribute of this TLV in the request
		    my $new_attr = {
			Name => $tlv, Type => 'tlv',
			Value => [ $attr ]
		    };
		    $request_tlvs{$tlv} = $new_attr;
		    push @a, $new_attr;
		} else {
		    my $tlv_list = $request_tlvs{$tlv}->{'Value'};
		    next unless ref($tlv_list); # should not happen
		    push @{$tlv_list}, $attr;
		}
	    } else {
		# normal attrbute, just copy over
		push @a, $attr;
	    }
	}

	for $a (@a) {
		$id = defined $dict_name{$a->{'Name'}}{'id'} ? $dict_name{$a->{'Name'}}{'id'} : int($a->{'Name'});
		$type = defined $a->{'Type'} ? $a->{'Type'} : $dict_name{$a->{'Name'}}{'type'};
		$vendor = vendorID($a);

		if ($vendor eq WIMAX_VENDOR) {
		    # WiMAX uses non-standard VSAs - include the continuation byte
		}

		unless (defined($value = $self->encodeValue($vendor, $id, $type, $a->{'Name'}, $a->{'Value'}))) {
			print STDERR "Unable to encode attribute $a->{Name} ($id, $type, $vendor) with value '$a->{Value}'\n" if $debug;
		    next;
		}
		print STDERR "Adding attribute $a->{Name} ($id, $type, $vendor) with value '$a->{Value}'\n" if $debug;
		if ( $vendor eq 'not defined' ) {
			$self->{'attributes'} .= pack('C C', $id, length($value) + 2) . $value;
		} else {
		    # VSA
		    # pack vendor-ID + vendor-type + vendor-length
		    if ($vendor eq WIMAX_VENDOR) {
			# add continuation byte
			$value = pack('N C C C', $vendor, $id, length($value) + 3, 0) . $value;
		    } else {
			$value = pack('N C C', $vendor, $id, length($value) + 2) . $value;
		    }
		    # add the normal RADIUS attribute header: type + length 
		    $self->{'attributes'} .= pack('C C', $dict_name{'Vendor-Specific'}{'id'}, length($value) + 2) . $value;
		}
	}
	return 1;
}

sub replace_attr_value {
	my ($self, $id, $value) = @_;
	my $length = length($self->{'attributes'});
	my $done = 0;
	my $cur_pos = 0;
	while ($cur_pos < $length) {
		my ($cur_id, $cur_len) = unpack('C C', substr($self->{'attributes'}, $cur_pos, 2));
		if ($cur_id == $id) {
			if (length($value) != ($cur_len - 2)) {
				if ($debug) {
					print STDERR "Trying to replace attribute ($id) with value which has different length\n";
				}
				last;
			}
			substr($self->{'attributes'}, $cur_pos + 2, $cur_len - 2, $value);
			$done = 1;
			last;
		}
		$cur_pos += $cur_len;
	}
	return $done;
}

sub calc_authenticator {
	my ($self, $type, $id, $length, $attributes) = @_;
	my ($hdr, $ct);

	$self->set_error;

	$hdr = pack('C C n', $type, $id, $length);
	$ct = Digest::MD5->new;
	$ct->add ($hdr, $self->{'authenticator'}, 
				(defined($attributes)) ? $attributes : $self->{'attributes'}, 
				$self->{'secret'});
	$ct->digest();
}

sub gen_authenticator {
	my ($self) = @_;
	my ($ct);

	$self->set_error;
	sub rint { int rand(2 ** 32 - 1) };
	$self->{'authenticator'} =
		pack "L4", rint(), rint(), rint(), rint();
}

sub encrypt_pwd {
	my ($self, $pwd) = @_;
	my ($i, $ct, @pwdp, @encrypted);

	$self->set_error;
	$ct = Digest::MD5->new();

	my $non_16 = length($pwd) % 16;
	$pwd .= "\0" x (16 - $non_16) if $non_16;
	@pwdp = unpack('a16' x (length($pwd) / 16), $pwd);
	for $i (0..$#pwdp) {
		my $authent = $i == 0 ? $self->{'authenticator'} : $encrypted[$i - 1];
		$ct->add($self->{'secret'},  $authent);
		$encrypted[$i] = $pwdp[$i] ^ $ct->digest();
	}
	return join('',@encrypted);
}
use vars qw(%included_files);

sub load_dictionary {
	shift;
	my ($file) = @_;
	my ($fh, $cmd, $name, $id, $type, $vendor, $dict_def_vendor, $tlv);

	$dict_def_vendor = 'not defined';
	undef($tlv);

	unless ($file) {
		$file = "/etc/raddb/dictionary";
	}
	# prevent infinite loop in the include files
	return undef if exists($included_files{$file});
	$included_files{$file} = 1;
	$fh = new FileHandle($file) or die "Can't open dictionary '$file' ($!)\n";
	print STDERR "Loading dictionary $file\n" if $debug;

	while (<$fh>) {
		chomp;
		($cmd, $name, $id, $type, $vendor) = split(/\s+/);
		next if (!$cmd || $cmd =~ /^#/);
		$cmd = lc($cmd);
		if ($cmd eq 'attribute') {
			if ( !$vendor ) {
			    if ( defined($dict_def_vendor)) {
				# Vendor was previously defined via BEGIN-VENDOR
				$vendor = $dict_def_vendor;
			    } else {
				$vendor = 'not defined';
			    }
			}

			$dict_name{$name}{'id'} = $id;
			$dict_name{$name}{'vendor'} = $vendor if $vendor;
			$dict_name{$name}{'type'} = $type;

			if (defined($tlv)) {
			    # inside of a TLV definition
			    $dict_id{$vendor}{$id}{'tlv'} = $tlv;
			    $dict_name{$name}{'tlv'} = $tlv;
			    # IDs of TLVs are only unique within the master attribute, not in the dictionary
			    # so we have to use a composite key
			    $dict_id{$vendor}{$tlv.'/'.$id}{'name'} = $name;
			    $dict_id{$vendor}{$tlv.'/'.$id}{'type'} = $type;
			} else {
			    $dict_id{$vendor}{$id}{'name'} = $name;
			    $dict_id{$vendor}{$id}{'type'} = $type;
			}
		} elsif ($cmd eq 'value') {
			next unless exists($dict_name{$name});
			$dict_val{$dict_name{$name}->{'id'}}->{$type}->{'name'} = $id;
			$dict_val{$dict_name{$name}->{'id'}}->{$id}->{'id'} = $type;
		} elsif ($cmd eq 'vendor') {
			$dict_vendor_name{$name}{'id'} = $id;
			$dict_vendor_id{$id}{'name'} = $name;
		} elsif ($cmd eq 'begin-vendor') {
			$dict_def_vendor = $name;
		} elsif ($cmd eq 'end-vendor') {
		    $dict_def_vendor = 'not defined';
		} elsif ($cmd eq 'begin-tlv') {
		    # FreeRADIUS dictionary syntax for defining WiMAX TLV
		    if (exists($dict_name{$name}) and $dict_name{$name}{'type'} eq 'tlv') {
			# This name was previously defined as an attribute with TLV type
			$tlv = $name;
		    }
		} elsif ($cmd eq 'end-tlv') {
		    undef($tlv);
		} elsif ($cmd eq '$include') {
			my @path = split("/", $file);
			pop @path; # remove the filename at the end
			my $path = ( $name =~ /^\// ) ? $name : join("/", @path, $name);
			load_dictionary('', $path);
		}
	}
	$fh->close;
#	print Dumper(\%dict_name);
	1;
}

sub set_error {
	my ($self, $error, $comment) = @_;
	$@ = undef;
	$radius_error = $self->{'error'} = (defined($error) ? $error : 'ENONE');
	$error_comment = $self->{'error_comment'} = (defined($comment) ? $comment : '');
	undef;
}

sub get_error {
	my ($self) = @_;

	if (!ref($self)) {
		return $radius_error;
	} else {
		return $self->{'error'};
	}
}

sub strerror {
	my ($self, $error) = @_;

	my %errors = (
		'ENONE',	'none',
		'ESELECTFAIL',	'select creation failed',
		'ETIMEOUT',	'timed out waiting for packet',
		'ESOCKETFAIL',	'socket creation failed',
		'ENOHOST',	'no host specified',
		'EBADAUTH',	'bad response authenticator',
		'ESENDFAIL',	'send failed',
		'ERECVFAIL',	'receive failed',
		'EBADSERV',	'unrecognized service',
		'EBADID',	'response to unknown request'
	);

	if (!ref($self)) {
	    return $errors{$radius_error};
	}
	return $errors{ (defined($error) ? $error : $self->{'error'} ) };
}

sub error_comment {
	my ($self) = @_;

	if (!ref($self)) {
		return $error_comment;
	} else {
		return $self->{'error_comment'};
	}
}

sub get_active_node {
	my ($self) = @_;
	return $self->{'node_addr_a'};
}

sub hmac_md5 {
	my ($self, $data, $key) = @_;
	my $ct = Digest::MD5->new;

	if (length($key) > $HMAC_MD5_BLCKSZ) {
		$ct->add($key);
		$key = $ct->digest();
	}
	my $ipad = $key ^ ("\x36" x $HMAC_MD5_BLCKSZ);
	my $opad = $key ^ ("\x5c" x $HMAC_MD5_BLCKSZ);
	$ct->reset();
	$ct->add($ipad, $data);
	my $digest1 = $ct->digest();
	$ct->reset();
	$ct->add($opad, $digest1);
	return $ct->digest();
}

sub _ascii_to_hex {
	my  ($string) = @_;
	my $hex_res = '';
	foreach my $cur_chr (unpack('C*',$string)) {
		$hex_res .= sprintf("%02X ", $cur_chr);
	}
	return $hex_res;
}


1;
__END__

=head1 NAME

Authen::Radius - provide simple Radius client facilities

=head1 SYNOPSIS

  use Authen::Radius;

  $r = new Authen::Radius(Host => 'myserver', Secret => 'mysecret');
  print "auth result=", $r->check_pwd('myname', 'mypwd'), "\n";

  $r = new Authen::Radius(Host => 'myserver', Secret => 'mysecret');
  Authen::Radius->load_dictionary();
  $r->add_attributes (
  		{ Name => 'User-Name', Value => 'myname' },
  		{ Name => 'Password', Value => 'mypwd' },
# RFC 2865 http://www.ietf.org/rfc/rfc2865.txt calls this attribute
# User-Password. Check your local RADIUS dictionary to find
# out which name is used on your system
#  		{ Name => 'User-Password', Value => 'mypwd' },
  		{ Name => 'h323-return-code', Value => '0' }, # Cisco AV pair
		{ Name => 'Digest-Attributes', Value => { Method => 'REGISTER' } }
  );
  $r->send_packet(ACCESS_REQUEST) and $type = $r->recv_packet();
  print "server response type = $type\n";
  for $a ($r->get_attributes()) {
  	print "attr: name=$a->{'Name'} value=$a->{'Value'}\n";
  }

=head1  DESCRIPTION

The C<Authen::Radius> module provides a simple class that allows you to 
send/receive Radius requests/responses to/from a Radius server.

=head1 CONSTRUCTOR

=over 4

=item new ( Host => HOST, Secret => SECRET [, TimeOut => TIMEOUT] 
	[,Service => SERVICE] [, Debug => Bool] [, LocalAddr => hostname[:port]]
	[,Rfc3579MessageAuth => Bool] [,NodeList= NodeListArrayRef])

Creates & returns a blessed reference to a Radius object, or undef on
failure.  Error status may be retrieved with C<Authen::Radius::get_error>
(errorcode) or C<Authen::Radius::strerror> (verbose error string).

The default C<Service> is C<radius>, the alternative is C<radius-acct>.
If you do not specify port in the C<Host> as a C<hostname:port>, then port
specified in your F</etc/services> will be used. If there is nothing
there, and you did not specify port either then default is 1645 for
C<radius> and 1813 for C<radius-acct>.

Optional parameter C<Debug> with a Perl "true" value turns on debugging
(verbose mode).

Optional parameter C<LocalAddr> may contain local IP/host bind address from 
which RADIUS packets are sent.

Optional parameter C<Rfc3579MessageAuth> with a Perl "true" value turns on generating
of Message-Authenticator for Access-Request (RFC3579, section 3.2).

Optional parameter C<NodeList> may contain a Perl reference to an array, containing a list of 
Radius Cluster nodes. Each nodes in the list can be specified using a hostname or IP (with an optional 
port number), i.e. 'radius1.mytel.com' or 'radius.myhost.com:1812'. Radius Cluster contains a set of Radius
servers, at any given moment of time only one server is considered to be "active"
(so requests are send to this server).  
How the active node is determined? Initially in addition to the C<NodeList> 
parameter you may supply the C<Host> parameter and specify which server should
become the first active node. If this parameter is absent, or the current
active node does not reply anymore, the process of "discovery" will be
performed: a request will be sent to all nodes and the consecutive communication
continues with the node, which will be the first to reply. 

=back

=head1 METHODS

=over 4

=item load_dictionary ( [ DICTIONARY ] )

Loads the definitions in the specified Radius dictionary file (standard
Livingston radiusd format). Tries to load 'C</etc/raddb/dictionary>' when no
argument is specified, or dies. NOTE: you need to load valid dictionary
if you plan to send RADIUS requests with attributes other than just
C<User-Name>/C<Password>.

=item check_pwd ( USERNAME, PASSWORD [,NASIPADDRESS] )

Checks with the RADIUS server if the specified C<PASSWORD> is valid for user
C<USERNAME>. Unless C<NASIPADDRESS> is specified, the script will attempt
to determine it's local IP address (IP address for the RADIUS socket) and
this value will be placed in the NAS-IP-Address attribute.
This method is actually a wrapper for subsequent calls to
C<clear_attributes>, C<add_attributes>, C<send_packet> and C<recv_packet>. It
returns 1 if the C<PASSWORD> is correct, or undef otherwise.

=item add_attributes ( { Name => NAME, Value => VALUE [, Type => TYPE] [, Vendor => VENDOR] }, ... )

Adds any number of Radius attributes to the current Radius object. Attributes
are specified as a list of anon hashes. They may be C<Name>d with their 
dictionary name (provided a dictionary has been loaded first), or with 
their raw Radius attribute-type values. The C<Type> pair should be specified 
when adding attributes that are not in the dictionary (or when no dictionary 
was loaded). Values for C<TYPE> can be 'C<string>', 'C<integer>', 'C<ipaddr>' or 'C<avpair>'.

=item get_attributes

Returns a list of references to anon hashes with the following key/value
pairs : { Name => NAME, Code => RAWTYPE, Value => VALUE, RawValue =>
RAWVALUE, Vendor => VENDOR }. Each hash represents an attribute in the current object. The 
C<Name> and C<Value> pairs will contain values as translated by the 
dictionary (if one was loaded). The C<Code> and C<RawValue> pairs always 
contain the raw attribute type & value as received from the server.
If some attribute doesn't exist in dictionary or type of attribute not specified 
then corresponding C<Value> undefined and C<Name> set to attribute ID (C<Code>
value).

=item clear_attributes

Clears all attributes for the current object.

=item send_packet ( REQUEST_TYPE, RETRANSMIT )

Packs up a Radius packet based on the current secret & attributes and
sends it to the server with a Request type of C<REQUEST_TYPE>. Exported
C<REQUEST_TYPE> methods are 'C<ACCESS_REQUEST>', 'C<ACCESS_ACCEPT>' ,
'C<ACCESS_REJECT>', 'C<ACCOUNTING_REQUEST>', 'C<ACCOUNTING_RESPONSE>',
'C<DISCONNECT_REQUEST>' and 'C<COA_REQUEST>'.
Returns the number of bytes sent, or undef on failure.

If the RETRANSMIT parameter is provided and contains a non-zero value, then
it is considered that we are re-sending the request, which was already sent
previously. In this case the previous value of packet indentifier is used. 

=item recv_packet ( DETECT_BAD_ID )

Receives a Radius reply packet. Returns the Radius Reply type (see possible
values for C<REQUEST_TYPE> in method C<send_packet>) or undef on failure. Note 
that failure may be due to a failed recv() or a bad Radius response 
authenticator. Use C<get_error> to find out.

If the DETECT_BAD_ID parameter is supplied and contains a non-zero value, then
calculation of the packet indentifier is performed before authenticator check 
and EBADID error returned in case when packet indentifier from the response
doesn't match to the request. If the DETECT_BAD_ID is not provided or contains zero value then 
EBADAUTH returned in such case.

=item get_error

Returns the last C<ERRORCODE> for the current object. Errorcodes are one-word
strings always beginning with an 'C<E>'.

=item strerror ( [ ERRORCODE ] )

Returns a verbose error string for the last error for the current object, or
for the specified C<ERRORCODE>.

=item error_comment

Returns the last error explanation for the current object. Error explanation 
is generated by system call.

=item get_active_node

Returns currently active radius node in standard numbers-and-dots notation with 
port delimited by colon. 

=back

=head1 AUTHOR

Carl Declerck <carl@miskatonic.inbe.net> - original design
Alexander Kapitanenko <kapitan at portaone.com> and Andrew
Zhilenko <andrew at portaone.com> - later modifications.

Andrew Zhilenko <andrew at portaone.com> is the current module's maintaner at CPAN.

=cut

