#+ session.pm - RPA session management ftns
#
# Copyright (c) 2003 System Management ARTS (SMARTS)
# All Rights Reserved.
#
# SMARTS provides this program 'as is' for educational and illustrative
# purposes only, without warranty or support.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/perlApi/perl/session.pm#7 $
# $Source: /src/MASTER/smarts/perlApi/perl/session.pm,v $
#
#PDF_TITLE=RPA Session management

=head1 NAME

InCharge::session - SMARTS InCharge domain manager session management.

=head1 COPYRIGHT

 Copyright (c) 2003 System Management ARTS (SMARTS)
 All Rights Reserved.

=head1 SYNOPSIS

 use InCharge::session;

 $session = InCharge::session->init( );

 $session = InCharge::session->new( "INCHARGE" );

 $session = InCharge::session->new(
     broker=>"localhost:426",
     domain=>"INCHARGE",
     username=>"noddy",
     password=>"bigears",
	 traceServer => 1
 );

 $object = $session->object( "Host::toytown1" );

 $object = $session->create( "Router::crossroads" );

 .. etc .. (lots of methods, described below)

=head1 DESCRIPTION

This module provides the mechanisms for accessing a SMARTS "InCharge" domain
server in a manner that is similar to that employed by InCharge's own ASL
scripting language. It provides the main access point to InCharge domains,
allowing scripts to establish client/server connections and to obtain
InCharge::object references which can be used to manipulate the objects in the
topology.

Refer to L<InCharge::intro> for an overview of this and the other InCharge::*
modules, and a simple tutorial description of how they are used.

=head1 FUNCTION GROUPS

InCharge::session provides access to four kinds of functions..

=over 4

=item B<session management>

Functions in this group are the principle functions of the module, they
are used for managing the perl client / domain manager connection.
Using these functions a script can attach, detach, listen for
events and create InCharge::object references.

=item B<InCharge primitives>

The InCharge::session module permits access to the low-level primitive
functions of the InCharge domain manager, allowing actions such
as "getClasses", "getInstances" etc to be performed. These "primitives"
don't all exactly mirror the interface provided by DMCTL or the native
ASL language. For example: DMCTL has a "save" command that does not have
an exact primitive equivalent, but there are two primitives that can be
invoked to give the same results. These are storeClassRepostity and
storeAllRepository. Where primitives exist that semantically match DMCTL
or ASL commands but differ in name, aliased names are provided to give
syntactic compatibility.

This man page does NOT detail these primitive methods; they are
documented in the InCharge::primitives man page.

=item B<utility functions>

This group includes functions to provide additional logical assistance
to writers of InCharge Perl scripts.

=item B<compatibility functions>

This group of functions provides wrappers around the primitives to
provide an interface that is more consistent with InCharge's native ASL
language and DMCTL utility.

Wrapper functions of this type are only provided for functions where the
syntax and semantics of the primitive is not compatible with ASL and/or
DMCTL. The "save" example has already been sited (above) to highlight
one such function.

=back

If you cant find the function you want in this manual page, then refer to
L<InCharge::primitives> or L<InCharge::object>.

=head1 ERROR HANDLING

RPA errors are reported back to the invoking script using perl's "die"
mechanism, and can be "caught" using "eval" (this is typical perl coding
practice, and mimics the try/throw/catch logic of java and C++).

For full details off these error handling conventions please refer to
L<InCharge::primitives>.

=head1 SESSION MANAGEMENT FUNCTIONS

The following session management functions are provided..

=over 4

=cut

package InCharge::session;
our $RET_NOK = -1;

# Pull in the other InCharge modules we need.
use InCharge::version;
use InCharge::remote;
use InCharge::object;
use InCharge::auth;

our $VERSION = substr $InCharge::version::version, 1;

# Pull in the standard perl modules we want.
use Socket;
use POSIX;
use Data::Dumper;
use IO::Handle;
use IO::File;
use IO::Socket;
use Getopt::Long;
use Sys::Hostname;
use Storable qw(dclone);

#$env_flow_val = uc($ENV{"SM_DISABLE_FLOW_WRAPPER"});
$env_flow_val = 1;

$NO_FLOW=0;
if ( $Config{"useshrplib"} eq "false" ) {
      # Since this perl was not built with a shared libperl
      # FlowWrapper is not supported.
      $NO_FLOW=1;
} else {
  if( ($env_flow_val eq "YES") || ($env_flow_val eq "Y") || ($env_flow_val eq "1") ){
    $NO_FLOW=1;
  }
  else{
     # Make sure it is version 5.8.8 to allow the flow...
     eval "require 5.8.8;" or $NO_FLOW=1;
     require InCharge::FlowWrapper unless $NO_FLOW;
  }
}


# Default timeout changed to 120 (from 15) as described in the PerlApi documentation
my $default_timeout = 120;   # In seconds.
my $DOWARN = 0;

BEGIN { $SIG{'__WARN__'} = sub { warn $_[0] if $DOWARN } }





#------------------------------------------------------------------------------
# A simple short-cut to InCharge::remote::throw. See remote.pm for comments.

sub throw {
    InCharge::remote::throw( @_ );
}

#------------------------------------------------------------------------------
# A simple short-cut to InCharge::remote::getFlowFileno. See remote.pm for comments.

sub getFlowFileno ($){
    my ($filehandle) = @_;
    InCharge::remote::getFlowFileno( $filehandle);
}

#------------------------------------------------------------------------------
# Low-level attach to an InCharge domain manager (or, indeed; the broker). Dont
# call this directly, but use InCharge::session->new or InCharge::session->init
# instead.

sub _attach ($$$$$$$) {

	# InCharge::session::_attach takes the following arguments..
    my (
		$ip,	    # the IP address (or resolvable host name) of the
		            # machine hosting the domain manager.
		$port,	    # the port to connect to the domain on
		$domain,    # the name of the InCharge domain
		$progname,  # a description of the script it's self
		$auth,	    # the uuencoded authentication information, or
		            # <undef> if not specified.
		$traceServer,	# true to request the domain manager server to
		                # trace our actions to it's stdout.
		$timeout    # the timeout for the link - this is how long we
		# are prepared to wait for primtives to complete.
	   ) = @_;

    my $handle = undef;
    my $mode = "unknown";
    my %reply = ( );
	
    # Whether we have been given an IP address or a host name - convert
    # it into an IP address. We do this by converting to the binary form
    # (which may do an NS lookup) then back to text (which just gives the
    # dotted-numeric notation).

    my ($ipbin, $ipstr);
	
    # Establish a socket connection with the domain manager.
    if ($NO_FLOW)
		{
			$ipbin = inet_aton( $ip );
			throw "[3] Cant resolve hostname" unless( defined $ipbin );
			$ipstr = inet_ntoa( $ipbin );
			$handle = eval { IO::Socket::INET->new(
												   PeerAddr => $ipstr,
												   PeerPort => $port,
												   Proto => "tcp"
												  ); };
			
			# bunk out if we couldnt get through.
			throw "[3] Cant connect to server $ipstr:$port"  
                           ." Error: $@"
                           ." handle: $handle"
                        if ( $@ or not $handle );
		}
    else
		{
			my $client =undef;
			
			# Since we are using the flows, we can let it resolve the ip etc.
			$ipbin = $ip;
			$ipstr = $ip;
			
			$handle = eval {
				new InCharge::FlowWrapper::FlowAPI();
			};
			if ($handle)
				{
					$client =  $handle->flowConnectToServer( $ipstr,$port);
				}
			
			# bunk out if we couldnt get through.
			throw "[3] _attach: Cant connect to server $ipstr:$port"
                           ." Error: $@"
                           ." handle: $handle"
                           ." client: $client"
				if ( $@ or not $handle or not $client);
		}

	InCharge::remote::initConnection($handle, $timeout);
	
	# Start to build the HTTP-like connection header packet. First we
	# choose the version number and authentication string..
	
	my ( $protover, $authheader );

	if (defined $auth) {
	    $protover = "4.5.1";
	    $authheader = "X-SMARTS-Client-Auth: $auth\r\n";
	} else {
	    $protover = "4.0.1";
	    $authheader = "";
	}

	# Now build the HTTP request message we are going to send to the
	# server to ask for a real session.
	InCharge::auth::__init();

        my $comment = $InCharge::version::comment;
        if ($comment) { $comment .= "; "; }

	my $agent = "Foundation-Perl-Client/" . $VERSION . " (".
	    $InCharge::version::buildnum . "; " . $comment.
            "Perl " . $] . "; " . $^O . ")";

	my $buff =
	    "POST /InCharge/V1.0/dmsocket/domain?$domain HTTP/1.0\r\n".
		"Content-type: application/x-smarts-socket\r\n".
		"Content-length: 0\r\n".
            	"User-Agent: $agent\r\n".
		"X-SMARTS-Protocol-Version: V$protover\r\n".
	    	$authheader.
		"X-SMARTS-Client-Host: ".InCharge::auth::hostname()."\r\n".
		"X-SMARTS-Client-PID: $$\r\n".
		"X-SMARTS-Client-Description: $progname\r\n".
		"X-SMARTS-Client-User: ".InCharge::auth::username()."\r\n".
		( $traceServer ? "X-SMARTS-Client-Trace: yes\r\n" : "" ).
		"\r\n";

	# Send it, and flush the output stream (so it really arrives)
    if ($NO_FLOW)
		{
			print $handle $buff;
			$handle->flush();
		}
    else
		{
			$len=length($buff);
			$handle->flowWrite($buff, length($buff));
			my $flush_ret = $handle->flowFlush();
			if( $flush_ret == $RET_NOK)
                {
                    throw "[13] Impossible to flush, connection lost!\n";
                }
		}

	# Collect the domain manager's reply (also HTTP), and store
	# the header fields in the "%reply" hash.
	
	
	if ($NO_FLOW)
		{
			while ( <$handle> ) {
				s/[\s]*$//;
				if ( m/^HTTP\/1.0\s+([0-9]+)\s+(.*)$/ ) {
					$reply{status} = $1;
					$reply{status_message} = $2;
				}
				if ( m/^([^:]+):\s*(.*)$/ ) {
					$reply{$1} = $2;
				}
				last if ( $_ eq "" );
			}
			
		}
    else
		{
			while ( $_ = $handle->flowReadline() ) {
				s/[\s]*$//;
				if ( m/^HTTP\/1.0\s+([0-9]+)\s+(.*)$/ ) {
					$reply{status} = $1;
					$reply{status_message} = $2;
				}
				if ( m/^([^:]+):\s*(.*)$/ ) {
					$reply{$1} = $2;
		    }
				last if ( $_ eq "" );
			}
		}
	# Check what we got back, and throw suitable errors, or set
	# flags accordingly.
    
	if ( $reply{status} == 401 ) {
	    throw "[4] Authentication failure for domain '$ip:$port/$domain'";
	} elsif ( $reply{status} == 199 ) {
	    $mode = "readonly";
	} elsif ( $reply{status} == 200 ) {
	    $mode = "read/write";
	} else {
	    throw "[5] [$reply{status}] Attach request to ".
		    "'$ip:$port/$domain' failed: ".$reply{status_message};
	}
	
    # Note all the information we need in a hash

    my %SOCK = (
				handle       => $handle,
				ip           => $ipstr,
				port         => $port,
				domain       => $domain,
				description  => $progname,
				connectReply => \%reply,
				access       => $mode
			   );

    # Get the time on the server, and the local time. These are needed
    # for some of the pseudo-events we generate when connection with the
    # domain manager is lost.
    my $time = eval { InCharge::remote::get(
											$handle, "SM_System", "SM-System", 
											"now" ); };
    # die $@ if ($@ and not( $@ =~ /Class of given name not found/));
    $SOCK{remoteConnectTime} = $time if (defined $time);
    $SOCK{localConnectTime} = time;
	
    # Get the protocol version number the server will accept, note it in
    # the session description, and report to InCharge::remote module. Version
    # numbers can be formatted as (showing the number mapped to) ..
    #	V1	=> 10000
    #	V1.2	    => 10200
    #	V1.2.3	    => 10203

    my $ver = $reply{"Protocol-Version"};
    throw "[9] No protocol-version in connection data" unless ( $ver );
	
    my $vn = 0;
	
    if ( $ver =~ m{^V(\d+)$} ) {
		$vn = $1 * 10000;
    } elsif ( $ver =~ m{^V(\d+)\.(\d+)$} ) {
		$vn = ( $1 * 10000 ) + ( $2 * 100 );
    } elsif ( $ver =~ m{^V(\d+)\.(\d+)\.(\d+)} ) {
		$vn = ( $1 * 10000 ) + ( $2 * 100 ) + ( $3 );
    } else {
		throw "[9] Unrecognised protocol-version in connection data";
    }

    $SOCK{protocolVersion} = $InCharge::remote::version[getFlowFileno($handle)] = $vn;
	
    # Pass back a reference to the hash containing the pertinant details.
	
    return \%SOCK;
}

#----------------------------------------------------------------------------
# low-level session closing. This closes the socket that has been used to
# communicate with the domain manager, and cleans up the blessed hash that
# has been used to encapsulate it. Dont use this call directly from within
# user scripts. Use "$session->detach();" instead.

sub _detach ($) {
    my ( $SOCK ) = @_;

    my $handle = $SOCK->{handle};

    # Close (shutdown) the socket itself.
	if($NO_FLOW){
		close( $handle ) if (defined $handle);
	}
	else{
	  #$handle->flowForceClose() if (defined $handle);
	  $handle->flowPhysClose() if (defined $handle);
	}

    # Clean out all the fields on the hash except the "args"
    # (which we can use to re-connected later).

    foreach my $k ( keys %{ $SOCK } ) {
		next if ( $k eq "args" );
		delete $SOCK->{$k};
    }
}

#-----------------------------------------------------------------------------
# Low-level attach to the observer feed socket of a domain manager. This
# establishes the socket connection down which the domain manager sends us
# notifications of subscribed events.

sub _attachCallback ($$$) {
    my ( $ip, $port, $key ) = @_;

    # Establish a socket connection with the domain manager. This is
    # actually a 2nd conncection since the main API link uses the
    # original, and we need a 2nd one for notifications to arrive on.

	my $handle=undef;

    if ($NO_FLOW)
    {
        $handle = eval { IO::Socket::INET->new(
											   PeerAddr => $ip,
											   PeerPort => $port,
											   Proto => "tcp"
											  ); };
		
		throw "[3] Cant connect to server $ip:$port" 
                ." Error: $@"
                   ." handle: $handle"
                   if ( $@ or not $handle );
    }
    else
		{
			my $client =undef;
			$handle = eval {
				new InCharge::FlowWrapper::FlowAPI();
			};
			if ($handle)
				{
					$client =  $handle->flowConnectToServer( $ip,$port);
				}
			
			# bunk out if we couldnt get through.
			throw "[3] _attachCallback: Cant connect to server $ipstr:$port" 
                           ." Error: $@"
                           ." handle: $handle"
                           ." client: $client"
				if ( $@ or not $handle or not $client);
		}

    InCharge::remote::initConnection($handle, -1);

	if ($NO_FLOW)
		{
			select $handle; $| = 1;
			select STDOUT;
		}
	
    # Build the HTTP request message and send it.
	
    my $buff =
		"POST /InCharge/V1.0/dmsocket/callback?$key HTTP/1.0\r\n".
		"Content-type: application/x-smarts-socket\r\n".
		"Content-length: 0\r\n".
		"\r\n";
    
    if ($NO_FLOW)
		{
			print $handle $buff;
			$handle->flush();
		}
    else
		{
			$len=length($buff);
			$handle->flowWrite($buff, $len);
			my $flushRet = $handle->flowFlush();
			if($flushRet == $RET_NOK)
				{
					throw "[13] Impossible to flush, connection lost!\n";
				}
		}
	
    # Collect the reply message (actually: we do nothing with it
    # once we've got it).

    if ($NO_FLOW)
		{
			while ( <$handle> ) {
				s/[\s]*$//;
				last if ( $_ eq "" );
			}

		}
    else
		{
			while ( $_ = $handle->flowReadline() ) {
				s/[\s]*$//;
				last if ( $_ eq "" );
			}
		}
	
    # Store the information we need in a hash
	
    my %SOCK = (
				handle      => $handle,
				ip          => $ip,
				port        => $port,
				observerkey => $key
			   );

    # and return it.

    return \%SOCK;
}

#-----------------------------------------------------------------------------
# _getProgName returns a name for the invoking program. This is used to pass
# to the domain manager at connect time if the script has not specified
# a description of it's own

my $_progNum = 0;
sub _getProgName () {
    $_progNum ++;
    return "Perl-Client-$$-$_progNum";
}

#-----------------------------------------------------------------------------
# Process the arguments passed to an InCharge::session->new( .. ) request, and
# set up defaults, derive broker-held information, etc.

sub _parseAttachArgs {
    my %in = ( );
    my %args = ( );


    # If we were given a single string as our argument, then
    # treat it as a domain name - and default everything else.

    if ( $#_ == 0 ) {
	$in{domain} = $_[0];
    } else { # otherwise we got a hash of stuff from the user.
	%in = @_;
    }

    # Pull information out the arguments passed to us, clean up
    # and store locally.

    my $broker = $in{broker};
    my $domain = undef;

    # The domain name can be either "domain => $name" or
    # "server => $name", according to taste.

    if (defined $in{server}) { $domain = $in{server}; }
    if (defined $in{domain}) { $domain = $in{domain}; }

    # Store the other possible parameters.

    if (defined $in{username} ) { $args{username} = $in{username}; }
    if (defined $in{user} )	{ $args{username} = $in{user};	   }
    $args{password} = $in{password};
    $args{description} = $in{description};


    if ( defined $in{traceServer} && $in{traceServer} =~ m{\s*-?\s*[0-9]+\s*$} ){
        $args{traceServer} = $in{traceServer};
    } else {
		# Warning is turned off by default
        warn "session.pm WARNING : No traceServer given or not an integer value. Using default = 0 \n";
        $args{traceServer} = 0;
    }

    if ( defined $in{timeout} && $in{timeout} =~ m{\s*-?\s*[0-9]+\s*$} ){
        $args{timeout} = $in{timeout};
    } else {
		# Warning is turned off by default
        warn "session.pm WARNING : No timeout given or not an integer value. Using default = $default_timeout \n";
        $args{timeout} = $default_timeout;
    }



    # If we have username and password, build them together into an
    # "auth" field. Insist that if we have either, we should actually
    # have both.

    if (defined($args{username}) and defined($args{password})) {
		$args{auth} = $args{username}.":".$args{password};
    } elsif ( !defined($args{username}) and !defined($args{password})) {
		$args{auth} = undef;
    } else {
		throw "[6] Either give both username and password to "
			."InCharge::session->new, or neither";
    }

    # Look at the environment to get the details of the broker we should
    # be using (if we havent already been told in the arguments supplied
    # by the user).

    $broker = $ENV{SM_BROKER} unless (defined $broker);
    $broker = $ENV{SM_BROKER_DEFAULT} unless (defined $broker);

    # If the broker string contains a ":", then split it up into host name
    # and port number.

    if ($broker) {
		if ( $broker =~ m/^([^:]*):([^:]*)$/ ) {
			$args{broker_host} = $1;
			$args{broker_port} = $2;
		} else {
			$args{broker_host} = $broker;
		}
    }

    # Supply the defaults for broker host and port if we dont know them
    # yet.

    $args{broker_port} = 426	 unless(defined $args{broker_port});
    $args{broker_host} = "localhost" unless(defined $args{broker_host});

    # If the domain name looks like "host:port/name", then split it up
    # into it's component parts.
    if ($domain) {
		if ( $domain =~ m(^([^:]*):([^/:]*)/(.*)$) ) {
			$args{domain_host} = $1;
			$args{domain_port} = $2;
			$args{domain_name} = $3;
		} else {
			$args{domain_name} = $domain;
		}
    }

    # Supply defaults for the domain name and script description (if they
    # arent known).
    $args{domain_name} = "INCHARGE" unless(defined $args{domain_name});
    $args{description} = _getProgName() unless(defined $args{description});

    # If we dont know the host name or port number for the domain manager,
    # then ask the broker.

    unless (
			defined($args{domain_host}) and
			defined($args{domain_port})
		   ) {
		# get any authentication data needed, for connecting to the
		# broker.
		
		my $auth = undef;
		my ( $user, $pass ) = InCharge::auth::getLoginAndPassword( "<BROKER>" );
		if (defined($user) and defined($pass)) { $auth = $user.":".$pass; }
		
		# establish a connection with the broker
		
		my $bsess = eval { _attach(
								   $args{broker_host},
								   $args{broker_port},
								   "dmbroker",
								   $args{description},
								   $auth,
								   undef,
								   $default_timeout
								  ); };
		
		# Throw an error if the connection attempt failed
		throw "[7] Can't connect to broker ".
			"'$args{broker_host}:$args{broker_port}'" 
                        ." Error: $@"
                        if $@;

		# try to get the domain host and port numbers using the
		# broker's "DomainManager" class.
		
		eval {
			$args{domain_port} = get(
									 $bsess,
									 "DomainManager",
									 $args{domain_name},
									 "port"
									);
			
			$args{domain_host} = get(
									 $bsess,
									 "DomainManager",
									 $args{domain_name},
									 "hostName"
									);
		};

		# Throw an error if the broker cant tell us the info we want.
		
		throw "[8] Cant find domain '$args{domain_name}' in "
			."broker '$args{broker_host}:$args{broker_port}'"
		 if $@;

                  eval {
			$args{domain_v6port} = get(
									 $bsess,
									 "DomainManager",
									 $args{domain_name},
									 "v6port"
									);
			
			$args{domain_v6host} = get(
									 $bsess,
									 "DomainManager",
									 $args{domain_name},
									 "v6hostName"
									);    
                        };
		
		
		# Close the connection with the broker.
		_detach( $bsess );
    }

    # If we dont have any authentication information, then use the clientConnect
    # file and logic to get them. This can result in an interaction with the
    # user.

    if ( !defined( $args{auth} ) ) {
		my ( $user, $pass ) =
		    InCharge::auth::getLoginAndPassword( $args{domain_name} );
		if (defined($user) and defined($pass)) {
			$args{username} = $user;
			$args{password} = $pass;
			$args{auth} = $user.":".$pass;
		}
    }

    # Return a reference to the hash containing all the arguments
    # and other information we have gleaned.
    return \%args;
}

#-----------------------------------------------------------------------------
# low-level listen for call-back events. This is used to receive data thrown
# to the client by the server in response to subscribed events.

sub _listenCallback ($) {
    my ( $sock ) = @_;

    my $reply = "";

    my $handle = $sock->{handle};

    # First off the wireline is an integer number which will have the
    # value "1" if all is ok.

    my $opcode = InCharge::remote::recvValue( $handle, "callback", "I" );
    if ($opcode != 1) {
	throw "[9] Invalid opCode; should get 1, but got $opcode";
    }

    # Next, the details of the event - 2 ints, 3 strings, 1 "anyval". Read
    # these and store in @info.

    my @info = InCharge::remote::recvValues( $handle, "callback", "IISSS*" );

    # Send a 0 byte to complete the handshake, and flush (to force it out).


    if ($NO_FLOW)
    {
    print $handle pack( "C", 0 );
    $handle->flush();
    }
    else
    {
        my $buff=pack( "C", 0 );
        my $buffLen = length($buff);
        $handle->flowWrite($buff, $buffLen);
        my $flushRet = $handle->flowFlush();
        if($flushRet == $RET_NOK)
        {
           throw "[13] Impossible to flush, connection lost!\n";
        }
    }

    # Return the event data as an array or array reference as appropriate.

    if (wantarray) {
	return ( 1, @info );
    } else {
	return [ 1, @info ];
    }
}

#-----------------------------------------------------------------------------
# Short cut to "_getObject" in InCharge::remote.

sub _getObject {
    my $session = shift @_;
    return InCharge::remote::_getObject( $session->{handle}, $_[0], $_[1] );
}

#-----------------------------------------------------------------------------
# AUTOLOAD is a standard perl function name. The fact that it exists in this module
# means that it is used to handle calls to functions that dont exist here. This
# is how we map things like
#
#   $reply = $session->getInstances($class)
#
# to 
#
#   $reply = InCharge::remote::primitive("getInstances", $session->{handle},
#			    $class)
#
# The first of these 2 syntax is the one that the script writers should use - it
# matches the ASL language conventions far more closely. Refer to the "perlsub"
# man page for details of how the AUTOLOAD mechanism works.

sub AUTOLOAD {
    my $session = shift @_;
    if ( $AUTOLOAD =~ m/([^:]+$)/ ) {
	return InCharge::remote::primitive( $1, $session->{handle}, @_ );
    } else {
	throw "[12] Invalid procedure name";
    }
}

#-----------------------------------------------------------------------

=item B<new>

 $session = InCharge::session->new( .. options .. );

This function establishes a connection between the calling perl script
and an InCharge domain manager, and returns a tied reference that
can be used thereafter to manipulate the domain and the entities
contained in its repository. Possible options are ..

=over

=item broker =E<gt> $host[:$port]

Specifies the InCharge broker from which the domain details are to be
lifted. The string consists of a host name or IP address followed by
an optional port number (delimited by a colon).

The default host is "localhost", and the default port is 426.

=item domain =E<gt> [$host:$port/]$domain

=item server =E<gt> [$host:$port/]$domain

This specifies the name of the domain to be used. If the host and port
details are also given, then RPA does not refer to the broker to determine
them.

The default domain name is "INCHARGE".

Note that the option name "server" can be used in place of "domain" -
the two options have the same meaning.

=item user =E<gt> $user_name

=item username =E<gt> $user_name

Specifies the name of the user to be used in connecting to the domain.  If if
"user" or "username" is specified, then "password" must also be specified. If
the username is not given, then RPA refers to the "clientConnect.conf" file to
determine the authentication information to use when establishing the
connection.

There is no default username.

If no username is specified, the script inspects and interprets the SM_AUTHORITY
environment variable in the same way that the main InCharge software does, and
may prompt the user for the user name and password using the standard I/O device.

=item password =E<gt> $password

This specifies the password for the user given with the "username" option.
Note that "username" and "password" must both be supplied, or neither of
them must be specified.

=item description =E<gt> $description

This describes the role of the script, and is noted by the server for use
in debug and other logging messages. It's contents are not significant
otherwise. The default is "Perl-Client".

=item traceServer =E<gt> 1

If specified, and given a "true" value (non-zero), then server-level tracing
is turned on. This causes the domain manager server to log information about
every primitive call invoked by the script - and can quickly fill up the
server's log file. It is recommended to use this sparingly since it also
has a negative impact on the server's performance.


=item timeout =E<gt> $timeout

Specifies the timeout to be tolerated while waiting for responses from the
domain manager to primitive requests. The default value is 120 seconds.
Take care not to make this too low, otherwise slow-to-process requests will
fail in a manner that looks like a comms link failure between the script and
the server.

=back

If only the domain name is given, it can be specified without the
"domain=>" key.

The username and password fields are required if connecting to a SAM
server, or an InCharge server with authentication features enabled. If
neither of these arguments is given, the "clientConnect.conf" file is
used to determine the username and password, or the mechanism to obtain
them.

=cut

sub new {
    my $pkg = shift @_;

    my @args_in = @_;

    # Process the sub arguments.

    my $args = _parseAttachArgs( @_ );

    # Attach to the domain manager (if possible)

	my ($host,$port);
	if ($ENV{"SM_IP_VERSIONS"} eq 'v6' ) {
		if (defined($args->{domain_v6host})) {
			$host = $args->{domain_v6host};		
			$port = $args->{domain_v6port};
		} 
	}
	if ($ENV{"SM_IP_VERSIONS"} eq 'v4') {
		$host = $args->{domain_host};		
		$port = $args->{domain_port};
	}
	if ($ENV{"SM_IP_VERSIONS"} eq 'v6v4') {
		if ( defined($args->{domain_v6host})) {
			$host = $args->{domain_v6host};		
			$port = $args->{domain_v6port};
		} else {
			$host = $args->{domain_host};		
			$port = $args->{domain_port};
		}
	}
	if ($ENV{"SM_IP_VERSIONS"} eq 'v4v6' ||
	   (! defined($host) && ! defined($port)) ) {
		if ( defined($args->{domain_host}) &&
			 $args->{domain_host} ne '0.0.0.0' ) {
			$host = $args->{domain_host};		
			$port = $args->{domain_port};
		} else {
			$host = $args->{domain_v6host};		
			$port = $args->{domain_v6port};
		}
	}
	return undef unless defined($host) and defined($port);

    my $session = _attach(
						  $host,
						  $port,
						  $args->{domain_name},
						  $args->{description},
						  $args->{auth},
						  $args->{traceServer},
						  defined($args->{timeout})
						  	? $args->{timeout} : $default_timeout
						 );
    unless (defined $session) {
		return undef;
    }

    # Blow away current cache contents for the connection, to
    # allow a clean start.

    InCharge::remote::initCache( $session->{handle} );

    # Store the specified arguments, for a possible future "reattach"
    # call.

    $session->{args} = { @args_in };

    # Return a blessed reference to the session object just created

    return bless $session, $pkg;
}

#-----------------------------------------------------------------------

=item B<init>

 $session = InCharge::session->init( );

This is the lazy man's version of InCharge::session-E<gt>new(). It parses
the scripts command line for you, looking for options that specify the
broker, server username, password and trace options. Then it invokes
InCharge::session-E<gt>new() with those arguments, and passes back the
result.

InCharge::session-E<gt>init() looks for the following script command line
arguments..

  --broker=<brokerIP[:bokerPort]>   (also: -b)
  --server=<domain-name>	    (also: -s)
  --user=<username>		    (also: -u)
  --password=<password>		    (also: -p)
  --traceServer
  --timeout

If neither the --user (or -u) and --password (or -p) are specified, the script
makes use of the SM_HOME/conf/clientConnect.conf file to determine the username
and password to be employed (see comments in the file for details of this
mechanism). This mechanism is turned on by specifying the value "<STD>" for the
SM_AUTHORITY environment variable.

If it encounters a command line syntax error, it calls usageError (in the main
script), which it is the developer's responsibility to provide. A single large
text string containing a description of the standard options handled is passed
as the argument to "usageError" - allowing the author to include information
about the standard options as well as any non standard ones he provides
himself. If the usageError subroutine does not exist, a default error message
is printed on STDERR.

Note that the "init" function consumes (removes) the command line arguments it
handles from @ARGV as it processes them; therefore you can access the @ARGV
array after it's execution to process additional arguments without worrying
about having to skip the "standard" ones, but you cannot use the init command
twice in the same script without saving and restoring the contents @ARGV first,
like this..

    @SAVE = @ARGV;
    $session1 = InCharge::session->init( );

    @ARGV = @SAVE;
    $session2 = InCharge::session->init( );


=cut

sub init () {
    my $pkg = shift @_;

    my $broker = undef;
    my $server = undef;
    my $username = undef;
    my $password = undef;
    my $traceServer = 0;
    my $timeout = $default_timeout;

    # parse the user's command line arguments. If a syntax error
    # is flagged up - then call "usageError" to report it.

    unless (GetOptions(
					   "broker=s" => \$broker,
					   "server=s" => \$server,
					   "user=s" => \$username,
					   "password=s" => \$password,
					   "traceServer" => \$traceServer,
					   "timeout" => \$timeout
					  )) {
		# Identify a "usageError" subroutine to use. We look back
		# down (up?) the caller stack until we find a perl package
		# that has a "usageError" function. The default action is
		# just to print to STDERR.
		
		my $scope = 0;
		my $uefunc = sub { print STDERR
							   "\nUsage: perl scriptname\n\n$_[0]\n"; exit(2); };
		while (my($pkg,$file,$line)=caller($scope)) {
			if ( exists ${$pkg."::"}{usageError} ) {
				$uefunc = $pkg . "::usageError";
			}
			$scope ++;
		}

		# Call the error subroutine we've found
		
		&{$uefunc}(
				   "  --broker=<brokerIP[:bokerPort]>	 (also: -b)\n".
				   "  --server=<domain-name>		 (also: -s)\n".
				   "  --user=<username>		 (also: -u)\n".
				   "  --password=<password>		 (also: -p)\n".
				   "  --traceServer\n".
				   "  --timeout=<timeout>\n"
				  );

		# return "undef" - indicating that something didnt work.
		return undef;
    }

    # If we get here - then the command lines args are ok - so let
    # "new()" do the real work.
    return new(
			   $pkg,
			   broker => $broker,
			   domain => $server,
			   username => $username,
			   password => $password,
			   traceServer => $traceServer,
			   timeout => $timeout,
			   @_
			  );
}

#-----------------------------------------------------------------------

=item B<broken>

 $flag = $session->broken( );

Returns non-zero (TRUE) if the session with the server is "broken" in some
way - this indicates connection or protocol failures, etc. To continue working
with a "broken" session, the script should call the "reattach()" function,
and then re-establish the event subscription profiles required.

=cut

sub broken ($) {
    my ( $session ) = @_;

    # it's broken if the session isnt valid
    return 1 unless (defined $session);

    # .. or if the socket handle isnt valid
    my $handle = $session->{handle};
    return 1 unless (defined $handle);

    # .. or if there is a "broken" error message stored for the
    # socket.
    return InCharge::remote::isBroken( $handle );
}

#-----------------------------------------------------------------------

=item B<ConnectionOpened>

 $flag = $session->ConnectionOpened( );

Returns non-zero (TRUE) if the TCP connection with the server is opened.
- this indicates connection was not closed by the KeepAlives, etc. To continue working
with a not "opened" connection, the script should call the "reattach()" function,
and then re-establish the event subscription profiles required.

=cut
sub ConnectionOpened ($) {
    my ( $session ) = @_;

    # it's broken if the session isnt valid
    return 0 unless (defined $session);

    # .. or if the socket handle isnt valid
    my $handle = $session->{handle};


    if (defined $handle)
		{
			return $handle->flowPhysIsOpen() ;
		}
    else
		{
			return 0;
		}
}
 
#-----------------------------------------------------------------------

=item B<reattach>

 $session->reattach( );

Re-establishes a connection that has been detached or broken. This can be
called to reconnect to a server to which the connection has been lost. Bear in
mind that re-establishing the connection does not automatically re-establish
observer sessions, subscriptions, transactional or other session state
information.

If the call is used to reattach a session which had an active observer, the
observer connection is closed as a side-effect of the action, and must be
re-opened separately.

This function should be called after an "[13] I/O Error" is thrown by any of
server access calls in order to shutdown and reopen the socket, thus cleaning
up the protocol. If this step is not taken there is a danger that residual
packets on the connection would cause synchronization problems between the RPA
client and server.

Note that reattach() doesn't return a new session identifier, but refreshes the
referenced one - so this is not a "dup()" style of action.

=cut

sub reattach ($) {
    my ( $session ) = @_;

    # if we're actually currently attached - detach now.

    if (defined $session->{handle}) {
		$session->detach();
    }

    # Open the new session using the remembered arguments from
    # the original one.
	
    my $new_session = InCharge::session->new( %{ $session->{args} } );

    # If that was ok - copy over any per-session information from
    # the new to the original, and junk the "new" copy. This leaves
    # us with the original session reattached.

    if (defined $new_session) {
		foreach my $key ( keys %{$new_session} ) {
			$session->{$key} = $new_session->{$key};
			delete $new_session->{$key};
		}
		undef $new_session;
    }
}



#-----------------------------------------------------------------------

=item B<detach>

 $session->detach( );

Detaches from the InCharge domain referred to by $session. This call can
be used for either an InCharge session ( created using
InCharge::session-E<gt>new() ) or an "observer" session ( created using
InCharge::session-E<gt>observer() ).

If this is used to detach a session with an active observer, the
observer is also closed.

This call does not completely destroy the $session reference contents,
but retains enough information to allow the session to be
re-established. Thus, it is possible to call $session-E<gt>reattach() to
re-connect to the server using the same parameters as were used in the
initial connection (however, the event subscriptions etc need to be
re-established explicitly in this event).

=cut

# variant for an observer session

sub detach_observer ($) {
    my ( $observer ) = @_;

    my $session = $observer->{session};

    delete $session->{observer}
	if (defined $session);

    InCharge::remote::initCache( $observer->{handle} )
	if (defined $observer->{handle});
	
    _detach( $observer );
	
    eval { InCharge::remote::purgeObserver( $session->{handle} ); }
		if (defined $session->{handle});
	
    return;
}

# variant for a domain manager connection

sub detach_session ($) {
    my ( $session ) = @_;

    if ( defined $session->{observer} ) {
		eval {
			detach_observer( $session->{observer} );
			InCharge::remote::purgeObserver( $session->{handle} );
		};
    }

    if (defined $session->{handle}) {
		InCharge::remote::initCache( $session->{handle} );
    }
	
    _detach( $session );

    return;
}

# The main function calls the relevant variant.

sub detach ($) {
    my ( $session ) = @_;

    if (defined $session->{observerkey}) {
		detach_observer( $session );
    } else {
		detach_session( $session );
    }
}

# we do a "detach" when the object is destroyed too (ie: if it
# goes out of context).

sub DESTROY {
    detach( @_ );
}

#------------------------------------------------------------------------

=item B<observer>

 $observer_session = $session->observer( .. options .. );

Creates (and returns a reference to) a connection to the domain manager for
subscribed events to be received on. This establishes a new socket between the
client and domain manager. Once connected; events can be subscribed to using
the various "subscribe" methods, and they can be received using..

    @event_info = $observer_session->receiveEvent( );

Specifying the option "connectEvents =E<gt> 1" to the "observer" function
causes server disconnection to be notified as a "DISCONNECT" event (rather than
an "[13] I/O Error"). However - unlike ASL; the re-connection is not performed
automatically - the script can use the $session-E<gt>reattach() call to attempt
an explicit re-connection, and must then re-establish any event subscriptions
and other contexts.

Specifying the option "ignoreOld =E<gt> 1" causes events generated before the
connection was established to be discarded automatically. The use of this
option is not generally recommended since the atomicity of time measurement on
NT and Unix makes it's results somewhat unpredictable.

Repeated calls to the observer() method of a session return references to the
same observer - it is not possible to create multiple observers on the same
session.

A separate document exists that describes the InCharge event subscription
mechanism as used from RPA.

=cut

sub observer ($%) {
    my ( $sock, @options ) = @_;

    # if we already have an active observer session - just
    # return the details.

    if (defined $sock->{observer}) {
	return $sock->{observer};
    }

    # Ask the domain manager for an observer key.

    $key = $sock->getObserverId( );

    # Establish the connection with the server

    my $session = _attachCallback( $sock->{ip}, $sock->{port}, $key );

    # take notes of important things

    $session->{domain} = $sock->{domain};
    $session->{session} = $sock;

    # discover the system clock settings on the server and locally

    my $time = eval { InCharge::remote::get( $sock->{handle},
					"SM_System", "SM-System", "now" ); };
    $session->{remoteConnectTime} = $time if (defined $time);
    $session->{localConnectTime}= time;

    # take a copy of the options specified (if any), and cache away
    # in the observer descriptor.

    while ( @options ) {
	my $key = shift @options;
	my $value = shift @options;
	$key =~ s/^-+//;
	$session->{options}->{$key} = $value;
    }

    # link the observer with it's parent DM session

    $sock->{observer} = $session;

    # bless it and send it on it's way

    return bless $session, "InCharge::session";
}

#-----------------------------------------------------------------------------

=item B<receiveEvent>

 @event = $observer_session->receiveEvent( [ $timeout ] );

This call is used to listen for subscribed events from the InCharge domain
manager. The received events are returned as an array or (in scalar context) a
reference to an array containing three or more elements. The details of the
significance of the different events are described in the document
"subscriptions".

The first element of all events is the time stamp (on the domain manager's
system clock - not the client's). The second is a string defining the event
type. The other elements are event specific.

The $timeout is optional, and specifies a timeout period (in seconds) that the
script is prepared to wait for an incoming event. If no event arrives in this
time period an event of type "TIMEOUT" is returned. The $timeout can be non
integer (eg: 0.25 = a quarter second).

A "DISCONNECT" event is returned if the API detects that the connection with
the server is broken (for example: if the server is halted). There are some
situations in which the operating system does not inform the perl client when
a break occurs - typically if it results from a cable disconnection or other
break that prevents the TCP/IP level packets getting through. In order to
over come this weakness of the underlying TCP/IP socket layer, the API will
check the connection with the server when a timeout is detected.
If a timeout period is specified, the API will test the connection with the server
when a timeout expires, and returns a DISCONNECT event if the test fails. This
test is NOT performed if no timeout is defined. Further: the test depends on
the timeout specified to the InCharge::session->new or InCharge::session->init
call used to establish the connection in the first place.

=cut

sub receiveEvent ($;$) {
    my ( $sock, $timeout ) = @_;

    my $fileno = getFlowFileno($sock->{handle});
    
    $timeout = -1 unless (defined $timeout);

    # check we're attached to the DM

    throw "[10] Not attached to an InCharge domain manager"
	unless (defined $sock->{handle});

    my @rtn = ( );  # this is were we store the event to return

    while ( 1 ) {
	# clear down the buffer in which we'll store the binary data we read
	# from the wireline.

	$InCharge::remote::rxbuff[$fileno] = "";

	# If a timeout has been specified - use unix's "select" to wait for the
	# that number of seconds for data to be available on the socket. If the
	# timeout expires then build a fake "TIMEOUT" event to pass back to the
	# calling script.

        if ($timeout != -1 && length($InCharge::remote::read_buffer[$fileno]) == 0) {

	    my ($rin, $rout, $eout) = ("","","");
                vec($rin, getFlowFileno($sock->{handle}), 1) = 1;

	    $rout = $eout = $rin;

                my $nfound;

                if($NO_FLOW) 
                { 
                    $nfound = select($rout, undef, $eout, $timeout);
                }
                else
                {
                    $nfound = $sock->{handle}->flowReadableNow($timeout);
                }


	    if ( $nfound < 1 ) {

                    my $time = time - $sock->{localConnectTime}	+ $sock->{remoteConnectTime};

		@rtn = ( $time, "TIMEOUT", $sock->{domain} );

		# Timeout - check that the session is still there
		eval { $sock->{session}->noop(); };
		if ( @$ ) {
		    delete $sock->{observerkey};
		    my $session = $sock->{session};
		    my $domain = $sock->{domain};
		    $sock->detach();
		    $session->detach();
		    @rtn = ( $time, "DISCONNECT", $domain );
		}
		last;
	    }
	}
	# Now we either know that there is data to be read, or the user
	# is happy to wait. So let's go get it..

	my @e = eval { $sock->_listenCallback(); };

	# If we got an error back, and it's a "disconnected" sort of
	# thing - then build a "DISCONNECTED" event to pass back to
	# the caller.
	if ( $sock->{options}->{connectEvents} and $@ =~ m/^\[13\]/ ) {
	    my $time = time - $sock->{localConnectTime}
		    + $sock->{remoteConnectTime};
	    delete $sock->{observerkey};
	    my $session = $sock->{session};
	    my $domain = $sock->{domain};
	    $sock->detach();
	    $session->detach();

	    @rtn = ( $time, "DISCONNECT", $domain );
	    last;
	}

	# Any other sort of error just gets thrown

	throw $@ if $@;


	# Reformat the event that we get to align with the ASL layout
	# more closely. We convert numeric codes to strings and strip out
	# unwanted fields.

	throw "[9] Invalid event received" unless ( $#e == 6 and $e[0] == 1 );

	     if ($e[1] == 2)    { @rtn = ( $e[2], "CLASS_LOAD", $e[3     ] );
	} elsif ($e[1] == 4)	{ @rtn = ( $e[2], "CREATE",	@e[3 .. 4] );
	} elsif ($e[1] == 32)	{ @rtn = ( $e[2], "DELETE",	@e[3 .. 4] );
	} elsif ($e[1] == 64)	{ @rtn = ( $e[2], "ATTR_CHANGE",@e[3 .. 6] );
	} elsif ($e[1] == 256)	{ @rtn = ( $e[2], "NOTIFY",	@e[3 .. 6] );
	} elsif ($e[1] == 1024) { @rtn = ( $e[2], "CLEAR",	@e[3 .. 5] );
	} elsif ($e[1] == 2048) { @rtn = ( $e[2], "ACCEPT",	@e[3 .. 5] );
	} elsif ($e[1] == 4096) { @rtn = ( $e[2], "REJECT",	@e[3 .. 5] );
	} elsif ($e[1] == 8192) { @rtn = ( $e[2], "SUSPEND",	@e[3 .. 6] );
	} elsif ($e[1] == 0x10000)
			    { @rtn = ( $e[2], "INFORMATION",     @e[3 .. $#e] );
	} elsif ($e[1] == 0x100000)
			    { @rtn = ( $e[2], "PROPERTY_ACCEPT", @e[3 .. $#e] );
	} elsif ($e[1] == 0x200000)
			    { @rtn = ( $e[2], "PROPERTY_REJECT", @e[3 .. $#e] );
	} elsif ($e[1] == 0x400000)
			    { @rtn = ( $e[2], "PROPERTY_SUSPEND",@e[3 .. $#e] );
	} else		    { @rtn = ( $e[2], $e[1],             @e[3 .. $#e] );
	}

	# Fake the "CERTAINTY_CHANGE" event if we think that's what should
	# be seen. This is a matter of comparing the "certainty" in the event
	# with the remembered certainly for a past occurance of the same
	# event.

	if ( $rtn[1] eq "CLEAR" or $rtn[1] eq "SUSPEND" ) {
	    delete $event_cache{
			    getFlowFileno($sock->{handle})}{join( "::", @rtn[2..4])
			    };
	} elsif ( $rtn[1] eq "NOTIFY" ) {
	    my $k1 = getFlowFileno($sock->{handle});
	    my $k2 = join( "::", @rtn[2..4] );
	    if (exists $event_cache{$k1}{$k2}) {
		next if ( $event_cache{$k1}{$k2} eq $rtn[5] );
		$rtn[1] = "CERTAINTY_CHANGE";
	    }
	    $event_cache{$k1}{$k2} = $rtn[5];
	}

	# If we have the "ignoreOld" option set, and the event we have got
	# ocurred BEFORE we started our listener session - then forget
	# about it and take another spin round the reception loop.

	last unless ( $sock->{options}->{ignoreOld} );
	last if ( $e[2] >= $sock->{remoteConnectTime} );
    }

    # Send back the event array (or reference to it).

    return wantarray ? @rtn : \@rtn;
}

#----------------------------------------------------------------------

=item B<object>

 $obj = $session->object( $objectname );

Creates a new InCharge::object reference that can be used to invoke methods of
the InCharge::object module. See L<InCharge::object> for full documentation on
how such a reference can be used.

As an example; to obtain the value of the Vendor field for a particular object,
you could use...

    $obj = $session->object( "::gw1" );
    $vendor = $obj->{Vendor};

You can even combine these into a single line, like this..

    $vendor = $session->object( "::gw1" )->{Vendor};

The $objectname parameter can be specified in any of the following styles ..

=over

=item B<object( 'Router::gw1' )>

A single string where both the class and instance name are specified, with two
colons delimiting them. If variables are to be used to specify the relevant
parts of the string, then it is important that at least the variable before
"::" is encased in braces because without them, perl will give the "::"
characters it's own meaning.

=item B<object( 'Router', 'gw1' )>

Two strings - one for the class and one for the instance name.

=item B<object( '::gw1' )>

One string, but with the class name missing. RPA will make a query to the
domain manager to discover the actual class for the object (hence: a minor
performance hit).

=item B<object( undef, 'gw1' )>

Two parameters, but the first one undefined. This also results in RPA
performing an DM query.

=item B<object( 'gw1' )>

A single parameter that doesn't include the "::" delimiter must contain just
the instance name. As above, a DM query is performed to determine the relevant
class name.

=back

An important difference between RPA and the native ASL language is that if you
create an object (using "object") in native ASL without specifying the class
name, the language assumes that the class "MR_Object" can be applied - this
restricts the level of property and operation access that can be used.  RPA
queries the repository to determine the actual class for the instance, giving
complete access to the resulting object's features.

=cut

sub object {
    # dead basic really - all the work is done by the
    # InCharge::object module.

    return InCharge::object->new( @_ );
}

#-----------------------------------------------------------------------

=item B<create>

 $obj = $session->create( $objectname );

Like "object" above, the "create" call creates an InCharge::object blessed
reference through which a specified repository instance can be manipulated.
However, unlike "object" above - the "create" method creates the object in the
repository if it doesn't already exist.

Since it has the ability to create objects, it is important that the object
name specified as an argument includes both the instance name AND the class
name. So you cannot use the "::instance" or (undef, $instance) syntaxes for
specifying the object name. You can however use either the "Class::Instance" or
($class, $instance) syntax described for the "object" method above.

Unlike the "createInstance" primitive (see L<InCharge::primitives>), it is not
an error to call the "create" method for an object instance that already exists
- in this case the call is equivalent to the "$session-E<gt>object" call above
and it just returns the InCharge::object blessed reference to the instance.

=cut

sub create {
    my $session = shift @_;

    # If the instance doesnt exist, create it
    unless( eval{ $session->instanceExists( @_ ); } ) {
	$session->createInstance( @_ );
    }

    # return the new object reference.
    return $session->object( @_ );
}

#-----------------------------------------------------------------------------

=item B<callPrimitive>

 RESULT = $session->callPrimitive( $primitiveName,
    @arguments )

Calls the specified DM primitive, passing it the arguments and returning it's
result. Note that for most primitives; this is a long-hand way of calling them.
It is only actually needed when a primitive and a method of the
InCharge::session module share the same name, and you wish to use the primitive
version.

So, the following are equivalent although the former is preferred..

    @list = $session->getInstances( "Router" );

    @list = $session->callPrimitive( "getInstances", "Router" );

The "put" primitive is one of the few where these two ways of calling it are
not equivalent. This is because the InCharge::session module exports it's own
variant of the method. So if you REALLY have to gain access to the primitive
version you will need to use the callPrimitive route - however this is not a
particularly good idea since the syntax is a little convoluted. See the
documentation on the "put" method later in this manual page for more details.

The type of the RESULT in array or scalar context is dependant on the primitive
being called. In general - if the primitive returns a scalar you get a scalar
or (in array context) a single element array. If the primitive returns an array
you get an array (in array context) or array reference (in scalar context).

Domain manager primitives are documented in L<InCharge::primitives>.

=cut

sub callPrimitive ($$@) {
    my ( $session, $pname, @args ) = @_;

    return InCharge::remote::primitive( $pname, $session->{handle}, @args );
}

#-----------------------------------------------------------------------------

=back

=head1 UTILITY FUNCTIONS

=over 4

=item B<TYPE>

 $number = $session->TYPE( $string );
 $string = $session->TYPE( $number );

Converts an InCharge domain manager data type mnemonic string to it's
internal numeric code (or visa versa). So the following prints "13".

 print $session->TYPE( "STRING" ) . "\n";

and.. the following code prints "STRING".

 print $session->TYPE( 13 ) . "\n";

The type names and codes are documented in L<InCharge::primitives>.

=cut

sub TYPE ($) {
    if ( $#_ > 0 && $_[0] =~ m/InCharge::/ ) {
	shift @_;
    }
    return InCharge::remote::TYPE( $_[0] );
}

#-----------------------------------------------------------------------------

=item B<getFileno>

 $fno = $session->getFileno( );

Returns the underlying system file number the refers to the socket used
for the script/server connection. This is useful when the script wishes
to use the perl "select" statement to listen for events from multiple
domain servers via multiple observer objects.


=cut

sub getFileno ($) {
    my ( $session ) = @_;
    
    return getFlowFileno($session->{handle});
    
}

#-----------------------------------------------------------------------

=item B<getProtocolVersion>

 $ver = $session->getProtocolVersion( );

Returns the protocol version number supported by the server. This is
a single integer number derived by the following calculation..

  ( major * 10000 ) + (minor + 100) + revision

So, a version of "V5.1" is represented by the number 50100, and "V4.2.1"
is represented by 40201.

=cut

sub getProtocolVersion ($) {
    my ( $session ) = @_;
    return $session->{protocolVersion};
}

#-----------------------------------------------------------------------

=item B<primitiveIsAvailable>

 $boolean = $session->primitiveIsAvailable( $primitive_name )

Checks whether the named primitive is available in the server. A value of 1
means that it is available, and value of 0 means that it is not - either
because it is an undefined primitive or was introduced in a later version
of the server software.

 if ( $session->primtiveIsAvailable( "getMultipleProperties" ) ) {
    ( $vendor, $model ) = $session->getMultipleProperties
	( $obj, [ "Vendor", "Model" ] );
 } else {
    $vendor = $obj->{Vendor};
    $model = $obj->{Model};
 }

=cut

sub primitiveIsAvailable ($$) {
    my ( $session, $primitive ) = @_;

    my $pver = InCharge::remote::getPrimitiveVersion( $primitive );
    return 0 if ( $pver == -1); # undefined primitive
    return ( $session->{protocolVersion} >= $pver ) ? 1 : 0;
}

=back

=head1 COMPATABILITY FUNCTIONS

The following functions add varying degrees of "wrapper" logic round the
InCharge primitives, to make them more compatible with the native ASL
language. If you are looking for ASL or DMCTL functions that don't appear
here, please refer to L<InCharge::primitives> or L<InCharge::object>.

=over 4

=item B<save>

 $session->save( $filename [, $class ] );

Saves the repository in the specified file. If a class name is specified
then just the instances of that class are saved.

=cut

sub save ($$;$) {
    my ( $sock, $file, $class ) = @_;

    if (defined $class) {
	return storeClassRepository( @_ );
    } else {
	return storeAllRepository( @_ );
    }
}

#-----------------------------------------------------------------------------

=item B<put>

 $session->put( $object, $property, $value );

It is not recommended to use this method extensively, instead you should
use the features of InCharge::object.

This method changes the value of an object property. This version
differs from the put_P primitive in that the latter requires the value
type to be specified explicitly whereas this version determines (and
caches) the type for you. The following calls are therefore equivalent
(the first is preferred)..

 $obj = $session->object( "Router::gw1" );
 $session->{Vendor} = "Cadbury";

 $obj->put( "Vendor", "Cadbury" );

 $obj->put( Vendor => "Cadbury" );

 $session->put( "Router::gw1", "Vendor", "Cadbury" );

 $session->object( "Router::gw1" )->{Vendor} = "Cadbury";

 $session->callPrimitive( "put_P", "Router", "gw1", "Vendor",
	[ "STRING", "Cadbury" ] );

When giving a value to an array property (such as the ComposedOf
relationship), then you should pass an array reference, like this..

 $obj->{ComposedOf} = [
    "Interface::IF-if1",
    "Interface::IF-if2"
 ];

Also; you can set more than one property in a single call. This can
reduce clutter in the layout of the script, but has little or no
performance advantage..

 $obj->put(
    Vendor   => "CISCO",
    Model    => "2500",
    Location => "Behind the coffee machine"
 );


=cut

# this code handles the "$session->put( object , property , value )"
# variant of the call. Just one property/value is allowed here.

sub put {
    # pull the arguments off the stack
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ( $prop, $value, $nope ) = @_;

    # verify that we have an expected argument set
    throw "[6] Wrong number/type or arguments to 'put'"
	unless (defined($session) and defined($class) and defined($instance)
	    and defined($prop) and defined($value) and !defined($nope));

    # get the type of the property we plan to set
    my $type = $session->getPropType( $class, $prop );
    $type = $session->TYPE( $type );

    throw "[6] Wrong Array type for argument. Expecting an array variable."
	    if ( (ref($value) ne "ARRAY") && $type =~ /_SET$/ );

    # call the primitive to do the work
    $session->put_P( $class, $instance, $prop, [ $type, $value ]);
}

#-----------------------------------------------------------------------------

=item B<invoke>

 RESULT = $session->invoke($object, $operation[, @arguments]);

It is not recommended to use this method extensively, instead you should
use the features of InCharge::object.

This method invokes the specified object operation, passing it the
listed arguments and returning the RESULT.

The type of the RESULT in array or scalar context is dependant on the
operation being called. In general - if it returns a scalar you get a
scalar or (in array context) a single element array. If it returns an
array you get an array (in array context) or array reference (in scalar
context).

Note that this method's semantics and syntax differ from the primitive
method invokeOperation in that the latter needs to have the types of the
arguments specified explicitly, where as this method (the
InCharge::session module version) discovers (and caches) the operation
argument types for you, and does not require the arguments to be listed
in arrays of array references.

Documentation about the operations that exist for a particular class can
be obtained using the RPA dashboard application, or listed using the
dmctl utility, like this..

 dmctl -s DOMAIN getOperations CLASSNAME

The following examples are equivalent (the first is preferred).

 $obj = $session->object( "Router::gw1" );
 $fan= $obj->findFan( 2 );

 $fan = $session->invoke( "Router::gw1", "findFan", 2 );

 $fan = $session->callPrimitive( "invokeOperation",
	"Router", "gw1", "findFan",
	[ [ "INT", 2 ] ]
 );

=cut

sub invoke {
    # pull the arguments of the stack
    my $session = shift @_;
    my ($class, $instance) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ($operation, @args) = @_;

    # verify that we have the expected number of args
    throw "[1] Wrong number/type or arguments to 'invoke'"
	unless (defined($session) and defined($class) and defined($instance)
	    and defined($operation));


    # get the list of arguments that the invoke() call is expecting
    my $sock = $session->{handle};
    my @argnames = InCharge::remote::getOpArgs( $sock, $class, $operation );

    # verify that the user hasnt given us more than this.
    throw "[1] Too many arguments to 'invoke'" if ( $#args > $#argnames );

    # build an array of argument types and values. We get the types
    # from the DM itself, using the getArgType primitive. Note that
    # this is flagged as a "caching" primitive, so the InCharge::remote
    # module remembers the reply we got the first time we call it, and
    # we never actually ask the DM the same question again.


    my @callargs = ( ); # here's where we'll store the arg types and values

    # iterate through the argument names

    foreach my $argname ( @argnames ) {
	last unless ( @args );	# stop if we've run out of values

	# get the argument type (from cache or DM as appropriate)

	my $argtype = InCharge::remote::getArgType(
					$sock, $class, $operation, $argname );

	push @callargs, [ $argtype, shift @args ];

    }

    # do the actual call and return the result.

    return InCharge::remote::invoke(
			    $sock, $class, $instance, $operation, \@callargs );
}

#-----------------------------------------------------------------------------

=item B<invoke_t> and B<invoke_T>

 ($type, $value) = $session->invoke_t(
     $object, $operation [, @arguments]
 );

 ($type, $value) = $session->invoke_T(
     $object, $operation [, @arguments]
 );

"invoke_t" is identical to "invoke" except that the return indicates
both the type and the value of the returned data. The value is a perl
scalar (if the operation returns a scalar) or an array reference (if the
operation returns an array). The type will contain one of the DM
internal type codes (for example: 13 for a string). These are documented
in L<InCharge::primitives>.

"invoke_T" is the same as "invoke_t" except that it also returns the types
of values embedded in structures and/or arrays.

=cut

# This follows the same logic as "invoke()", above - but adds the type of
# the returned value to what is passed back to the caller.

sub invoke_t {
    my $session = shift @_;
    my ($class, $instance) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ($operation, @args) = @_;

    throw "[1] Wrong number/type or arguments to 'invoke_t'"
	unless (defined($session) and defined($class) and defined($instance)
	    and defined($operation));
    my $sock = $session->{handle};

    my @argnames = InCharge::remote::getOpArgs( $sock, $class, $operation );
    throw "[1] Too many arguments to 'invoke_t'" if ( $#args > $#argnames );
    my @callargs = ( );
    foreach my $argname ( @argnames ) {
	last unless ( @args );
	my $argtype = InCharge::remote::getArgType(
					$sock, $class, $operation, $argname );
	push @callargs, [ $argtype, shift @args ];
    }
    return InCharge::remote::invoke_t(
			    $sock, $class, $instance, $operation, \@callargs );
}

sub invoke_T {
    my $session = shift @_;
    my ($class, $instance) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ($operation, @args) = @_;

    throw "[1] Wrong number/type or arguments to 'invoke_T'"
	unless (defined($session) and defined($class) and defined($instance)
	    and defined($operation));
    my $sock = $session->{handle};

    my @argnames = InCharge::remote::getOpArgs( $sock, $class, $operation );
    throw "[1] Too many arguments to 'invoke_T'" if ( $#args > $#argnames );
    my @callargs = ( );
    foreach my $argname ( @argnames ) {
	last unless ( @args );
	my $argtype = InCharge::remote::getArgType(
					$sock, $class, $operation, $argname );
	push @callargs, [ $argtype, shift @args ];
    }
    return InCharge::remote::invoke_T(
			    $sock, $class, $instance, $operation, \@callargs );
}

#----------------------------------------------------------------------

=item B<findInstances>

 @instances = $session->findInstances( $c_patn, $i_patn [, $flags] )

or

 @instances = $session->findInstances( "${c_patn}::${i_patn}" [, $flags] )

Finds instances that match the class and instance patterns, according to rules
specified in the flags.

The $flags is a set of characters that modifies the way the call works.

A flag of "n" means that subclasses are NOT recursed into - so instances in
matching classes only are returned. Without "n", instances of matching classes
AND their subclasses are returned.

A flag of "r" means that unix-like RegEx matching is used during the search. If
the "r" flag is not specified, the search uses InCharge "glob" pattern
matching.

The default is no flags - ie: "glob" matches and recursion.

Results are returned as a list of strings, each of which contains a class and
instance name, delimited with "::".

Note that the search strings are "anchored" as if the "^" and "$" had been used
in the unix-style pattern. So "rr*" matches "rred" but not "herring", whereas
"*rr*" matches both of them.

Example:

 @found = $session->findInstances( "Router::gw*", "n" );


=cut

sub findInstances {
    my $session = shift @_;
    my $c_patn = shift @_;
    my $i_patn;

    if ( $c_patn =~ m{^(.*?)::(.*)$} ) {
	$c_patn = $1;
	$i_patn = $2;
    } else {
	$i_patn = shift @_;
    }
    my ( $flags, $nowt ) = @_;

    throw("[1] findInstances: argument error")
	if ( !defined($c_patn) or !defined($i_patn) or defined($nowt));

    my $n_flag = 0;
    my $r_flag = 0;

    foreach my $flag ( split(//, lc( $flags ) ) ) {
	if ( $flag eq "n" ) { $n_flag = 1; }
	elsif ( $flag eq "r" ) { $r_flag = 1; }
	else { throw( "[1] findInstances: bad flag(s)"); }
    }

    my $nflag = ($n_flag ? 0 : 0x001000) + ($r_flag ? 0 : 0x100000);

    return $session->findInstances_P( $c_patn, $i_patn, $nflag );
}

#----------------------------------------------------------------------

=item B<getCauses>

 @events = $session->getCauses( $objectname, $event [, $oneHop] );

The getCauses function returns a list of problems that cause an event.
The function receives arguments: class, instance (possibly combined into
one) and event. The function returns the problems that cause the event
based on the relationships among instances defined in the InCharge
Domain Manager.

The oneHop parameter is optional. If it is omitted or passed as FALSE,
the full list of problems explaining eventname, whether directly or
indirectly, is returned. If it is passed as TRUE, only those problems
that directly list eventname among the events they explain are returned.

The function returns an array of array references with the format:

    [
      [ <classname::instancename>,<problemname> ],
      [ <classname::instancename>,<problemname> ],
	...
    ]

Note that the class and instance names are returned as a single "::"
delimited string - giving us two strings per returned event in total.
This is different from the native ASL language which returns the class
and instance names separately, giving three strings for each event.

Example:

 @causes = $session->getCauses(
    "Router::gw1", "MightBeUnavailable"
 );

=cut

sub getCauses {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my $event = shift @_;
    my $oneHop = shift @_;
    throw "[1] getCauses: argument error"
	unless (defined $event and $#_ == -1);
    $oneHop = 0 unless (defined $oneHop);
    my @events = $session->getEventCauses( $class, $instance, $event, !$oneHop );
    my @rtn = ( );
    foreach my $e ( @events ) {
	push @rtn, [
	    join( "::", InCharge::remote::_getObject(undef, [ $e->[2] ], 0) ),
	    $e->[3]
	];
    }
    return wantarray ? @rtn : \@rtn;
}

=item B<getClosure>

 @events = $session->getClosure($object, $eventname[, $oneHop]);

The getClosure function returns a list of symptoms associated with a problem or
aggregation. The function returns the symptoms associated with the problem or
aggregate based on the relationships among instances defined in the InCharge
Domain Manager.

The oneHop parameter is optional. If it is omitted or passed as FALSE, the full
list of problems explaining eventname, whether directly or indirectly, is
returned. If it is passed as TRUE, only those problems that directly list
eventname among the events they explain are returned.

The function returns an array of array references with the format:

    [
      [ <classname::instancename>,<problemname> ],
      [ <classname::instancename>,<problemname> ],
	...
    ]

Note that the class and instance names are returned as a single "::" delimited
string - giving us two strings per returned event in total.  This is different
from the native ASL language which returns the class and instance names
separately, giving three strings for each event.

Example:

 @symptoms = $session->getClosure( "Router::gw1", "Down", 0 );

=cut

sub getClosure {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my $event = shift @_;
    my $oneHop = shift @_;
    throw "[1] getClosure: argument error"
	unless (defined $event and $#_ == -1);
    $oneHop = 0 unless (defined $oneHop);
    my $type = $session->getEventType( $class, $event );

    my ( @events, $skip );

    if ( $type eq "AGGREGATION" ) {
	@events = $session->getAggregationEvents(
					$class, $instance, $event, !$oneHop );
	$skip = 0;

    } elsif ( $type eq "PROBLEM" ) {
	@events = $session->getProblemClosure(
					$class, $instance, $event, !$oneHop );
	$skip = 2;

    } else {
	@events = ( );
	$skip = 0;
    }

    my @rtn = ( );

    foreach my $e ( @events ) {
	push @rtn, [
	    join( "::", InCharge::remote::_getObject(undef,
					[ $e->[$skip] ], 0) ), $e->[$skip+1]
	];
    }

    return wantarray ? @rtn : \@rtn;
}

#---------------------------------------------------------------------------

=item B<getExplains>

 @events = $session->getExplains($object, $eventname[, $onehop ]);

MODEL developers can add information to a problem in order to
emphasize events that occur because of a problem. The getExplains
function returns a list of these events.

The $onehop parameter is optional. If it is omitted or passed as FALSE (0),
the full list of problems explaining $eventname, whether directly or
indirectly, is returned. If it is passed as TRUE (1), only those problems
that directly list eventname among the events they explain are returned.

The function returns an array of array references with the format:

    [
      [ <classname::instancename>,<problemname> ],
      [ <classname::instancename>,<problemname> ],
	...
    ]

Note that the class and instance names are returned as a single "::"
delimited string - giving us two strings per returned event in total.
This is different from the native ASL language which returns the class
and instance names separately, giving three strings for each event.

=cut

sub getExplains {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0);
    my ( $event, $onehop, $nowt ) = @_;
    throw "[1] InCharge::session::getExplains - wrong number of arguments"
	unless (defined($event) and !defined($nowt));
    $onehop = 0 unless (defined $onehop);
    my @events = InCharge::remote::getProblemExplanation(
	$session->{handle}, $class, $instance, $event, !$onehop
    );
    foreach ( @events ) {
	shift @{$_};
	shift @{$_};
    }
    return wantarray ? @events : \@events;
}

#-----------------------------------------------------------------------------

=item B<getExplainedBy>

 @events = $session->getExplainedBy($object, $event[, $onehop ]);

This function is the inverse of the getExplains() function: It returns those
problems which the MODEL developer has listed as explaining this problem.

The $onehop parameter is optional. If it is omitted or passed as FALSE,
the full list of problems explaining $event, whether directly or
indirectly, is returned. If it is passed as TRUE, only those problems
that directly list $event among the events they explain are returned.

The function returns an array of array references with the format:

    [
      [ <classname::instancename>,<problemname> ],
      [ <classname::instancename>,<problemname> ],
	...
    ]

Note that the class and instance names are returned as a single "::"
delimited string - giving us two strings per returned event in total.
This is different from the native ASL language which returns the class
and instance names separately, giving three strings for each event.

=cut

sub getExplainedBy {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0);
    my ( $event, $onehop, $nowt ) = @_;
    throw "[1] InCharge::session::getExplainedBy - wrong number of arguments"
	unless (defined($event) and !defined($nowt));
    $onehop = 0 unless (defined $onehop);
    my @events = InCharge::remote::getEventExplainedBy(
	$session->{handle}, $class, $instance, $event, !$onehop
    );
    foreach ( @events ) {
	shift @{$_};
	shift @{$_};
    }
    return wantarray ? @events : \@events;
}

#-----------------------------------------------------------------------------

=item B<subscribe> and B<unsubscribe>

 $session->subscribe( $C, $I, $E [, $flags ] );
 $session->subscribe( "$C::$I::$E[/$flags]" );
 $session->unsubscribe( $C, $I, $E [, $flags ] );
 $session->unsubscribe( "$C::$I::$E[/$flags]" );

These functions subscribe (unsubscribe) to notifications of the specified events.
'$C', '$I', '$E' must be regexp patterns representing the classes,
instances, and events to which to subscribe.

"unsubscribe" is the reverse of "subscribe".

The $flags value is a combination of the values in the following table
or a more menonic string (see below).

    0x000001 = Simple event
    0x000002 = Simple aggregation
    0x000010 = Problem
    0x000020 = Imported event
    0x000040 = Propagated aggregation
    0x0000ff = All
    0x001000 = Expand subclasses
    0x002000 = Expand subclasses events
    0x004000 = Expand aggregations
    0x008000 = Expand closures
    0x010000 = Sticky
    0x020000 = Undo all
    0x040000 = Quiet accept
    0x080000 = Quiet suspend
    0x100000 = Glob

As a compatibility aid, the $flag can also be specified as a string of letters
- in this case, each of the letters are subscription qualifiers: 'p' means
subscribe to problems; 'a' means subscribe to aggregates (impacts); and 'e'
means subscribe to events. If none of these are present, 'p' is assumed. 'v'
means run in verbose mode, which turns on subscription control messages. The
action of these options is the same as that provided by the --subscribe= option
of the InCharge sm_adapter program.

Examples:

    $session->subscribe( "Router", ".*", ".*", "/pev" );
    $session->subscribe( "Router::.*::.*/peav" );
    $session->subscribe( $obj, ".*", 0x3 );
    $session->unsubscribe( $obj, ".*", 0x3 );

Refer to L<InCharge::primitives> for the subscribeTopology and other
subscription types.

=cut

sub _subscribe_args {
    my $session = shift @_;
    my ( $class, $instance, $event, $flags ) = eval {
	if ( $#_ == 0 ) {
	    split( /[:\/]+/, $_[0] );
	} else {
	    ( InCharge::remote::_getObject( $session->{handle}, \@_, 0), @_ );
	}
    };

    unless (defined $flags) {
	$flags = "/p";
    }

    if ( $flags =~ m{^[/peavPEAV]+$} ) {
	my $nflag = 0x000d3000;
	$nflag	|=  0x00000010 if ($flags =~ s/[pP]//g );
	$nflag	|=  0x00000042 if ($flags =~ s/[aA]//g );
	$nflag	|=  0x00000021 if ($flags =~ s/[eE]//g );
	$nflag	&= ~0x000c0000 if ($flags =~ s/[vV]//g );
	throw "[1] Bad flags list for subscribe" if ( $flags !~ m{^/*$} );
	$flags = $nflag;
    }
    return ($session->{handle}, $flags, $class, $instance, $event);
}

sub subscribe {
    return InCharge::remote::subscribeAll(
	_subscribe_args( @_ )
    );
}

sub unsubscribe {
    return InCharge::remote::unsubscribeAll(
	_subscribe_args( @_ )
    );
}

#-------------------------------------------------------------------------

=item B<transaction>, B<abortTxn> and B<commitTxn>

 $session->transaction( [ $flag ] );
 $session->abortTxn( );
 $session->commitTxn( );

Transactions, Commit and Abort

When you modify objects In InCharge Perl scripts, the objects change as
each modification occurs. Using transactions, you can commit many
changes to the objects in an InCharge Domain Manager as a single change
or choose to abort all of them. Use the following syntax to create a
transaction:

    $session->transaction();

After you initiate the transaction, every change made to an object does
not affect the object until you commit the transaction. If the you abort
the transaction, any changes made will not affect the object. Use the
following syntax to either commit or abort a transaction:

    $session->commitTxn( );

    or

    $session->abortTxn( );

The changes made with a transaction are not visible outside of the
script until you commit the changes. Within a transaction, the same
script can see the proposed changes. Transactions also can control how
other applications see objects before changes are committed or aborted
by adding a single keyword. The syntax of a transaction with a keyword
is:

 $session->transaction(["WRITE_LOCK"|"READ_LOCK"|"NO_LOCK"]);

A keyword can be any one of the following:

 KEYWORD       DESCRIPTION
 -----------   ----------------------------
 WRITE_LOCK    While the transaction is open, no other
	       process can modify or access information
	       in the repository.
 READ_LOCK     Currently behaves as WRITE_LOCK.
 NO_LOCK       This is the default behavior. No locks exist
	       until the script commits the transaction.

You can nest transactions. When you nest a transaction, you must commit or
abort the nested transaction before you commit or abort the previous
transaction.

RPA aborts any open transactions when the script terminates.

Example::

    #! /usr/local/bin/perl
    $session = InCharge::session->init( );
    $delthis = shift @ARGV;
    $delthisObj = $session->object($delthis);
    @relObj = @{ $delthisObj->{ComposedOf} };

    $session->transaction();
    $x = $delthisObj->delete();
    foreach $mem (@relObj) {
	$mem->delete();
    }
    $session->commitTxn();
    print("Deleted ".delthis." and related ports\n");

Explanation: This script deletes a card and its related ports. The
script is invoked with an argument that specifies the card to delete.
Using the ComposedOf relationship, the script creates a list of Port
objects to delete. The script deletes the card and its related ports at
the same time through a transaction.

=cut

sub transaction ($;$) {
    my ( $session, $flag ) = @_;
    $flag = 0 unless (defined $flag);

    $flag =~ s/[_-]//g;
    my $n = { NOLOCK=>0, READLOCKONLY=>1, READLOCK=>2, WRITELOCK=>3 }->
								{uc($flag)};
    $flag = $n if (defined $n);

    throw "[6] Bad flag for InCharge::session::transaction"
	unless (isdigit($flag));

    throw "[6] Flag out of range for InCharge::session::transaction"
	unless( $flag >= 0 and $flag <= 3 );

    return InCharge::remote::transactionStart( $session->{handle}, $flag );
}

sub commitTxn ($) {
    my ( $session ) = @_;
    return InCharge::remote::transactionCommit( $session->{handle} );
}

sub abortTxn ($) {
    my ( $session ) = @_;
    return InCharge::remote::transactionAbort( $session->{handle} );
}

#---------------------------------------------------------------------------

=item B<delete>

 $session->delete( $object );

Deletes the specified object instance from the repository. Note that
this does not clean up all the object inter-dependencies and links. For
a cleaner object deletion, use the "remove" operation (if one exists)
for the object class in question (see 'invoke').

The delete method can be called in one of two ways..

    $session->delete( $object );
 or
    $object->delete();

For details of the latter method, see L<InCharge::object>.

=cut

sub delete {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ( $nowt ) = @_;
    throw "[1] InCharge::session::delete - wrong number of arguments"
	unless (defined($session) and !defined($nowt));
    return InCharge::remote::deleteInstance(
					$session->{handle}, $class, $instance );
}

#---------------------------------------------------------------------------

=item B<getEventType>

 $type = $session->getEventType( $class, $event );

Given a class and event name, this call returns a string that describes the
type of the event. The possible strings returned are..

    EVENT
    AGGREGATION
    SYMPTOM
    PROBLEM
    UNKNOWN (indicates an error)

Example:

 $type = $session->getEventType( "Router", "Down" );

If you wish to obtain the low-level numeric type codes instead of descriptive
strings you can use the "getEventType" primitive, thus..

 $type = $session->primitive( "getEventType", "Router", "Down" );

=cut

my %event_types = (
    0 => "EVENT",
    1 => "AGGREGATION",
    2 => "SYMPTOM",
    4 => "PROBLEM",
    6 => "AGGREGATION",
    7 => "SYMPTOM"
);

sub getEventType ($$$) {
    my ( $session, $class, $event ) = @_;
    my $type = $session->getEventType_P( $class, $event );
    my $type_str = $event_types{ $type };
    $type_str = "UNKNOWN" unless (defined $type_str);
    return $type_str;
}

#---------------------------------------------------------------------------

=item B<getServerName>

 $session->getServerName( );

Returns the name of the InCharge domain manager to which the InCharge session is
connected.

=cut

sub getServerName ($) {
    my ( $session ) = @_;
    return $session->{domain};
}

#---------------------------------------------------------------------------

=item B<insertElement>

 $session->insertElement( $object, $relation, @item[s] );

Inserts one or more elements into an object relationship or table. It is
suggested that you use the insertElement feature of the InCharge::object
module instead, thus..

    $obj->insertElement( $relation, @item[s] );

See L<InCharge::object> for details.

=cut

sub insertElement {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ( $relation, @items ) = @_;
    throw "[1] InCharge::session::insertElement - wrong number of arguments"
	unless (
	    defined($session)
	    and defined($class)
	    and defined($instance)
	    and defined($relation)
	    and $#items >= 0
	);

    my $type = $session->getPropType( $class, $relation );
    $type = $session->TYPE( $type );
    $type =~ s/_SET$//;

    while ( @items ) {
	my $arg = shift( @items );
	$session->insertElement_P( $class, $instance, $relation, [ $type, $arg ] );
    }

    return undef;

#    while ( @items ) {
#	if (ref($items[0]) eq "ARRAY") {
#	    my $arg = shift( @items );
#	    $session->insertElement_P(
#		$class, $instance, $relation, $arg
#	    );
#	} else {
#	    my ( $class2, $instance2) = InCharge::remote::_getObject(
#		$session->{handle}, \@items, 0
#	    );
#	    $session->insertElement_P(
#		$class, $instance, $relation,
#		[ "OBJREF", "${class2}::${instance2}" ]
#	    );
#	}
#   }
#
#    return undef;
}

#-------------------------------------------------------------------------

=item B<removeElement>

 $session-E>removeElement( $object, $relation, @item[s] );

removes one or more elements from an object relationship (such as
"ComposedOf") or anyval-array table. It is suggested that you use
the removeElement feature of the InCharge::object module instead,
thus..

    $obj->removeElement( $relation, @item[s] );

See L<InCharge::object> for details.

=cut

sub removeElement {
    my $session = shift @_;
    my ( $class, $instance ) =
		    InCharge::remote::_getObject( $session->{handle}, \@_, 0 );
    my ( $relation, @items ) = @_;
    throw "[1] InCharge::session::removeElement - wrong number of arguments"
	unless (
	    defined($session)
	    and defined($class)
	    and defined($instance)
	    and defined($relation)
	    and $#items >= 0
	);

    my $type = $session->getPropType( $class, $relation );
    $type = $session->TYPE( $type );
    $type =~ s/_SET$//;

    while ( @items ) {
	my $arg = shift( @items );
	$session->removeElement_P( $class, $instance, $relation, [ $type, $arg ] );
    }

    return undef;

#    while ( @items ) {
#	if (ref($items[0]) eq "ARRAY") {
#	    my $arg = shift( @items );
#	    $session->removeElement_P(
#		$class, $instance, $relation, $arg
#	    );
#	} else {
#	    my ( $class2, $instance2) = InCharge::remote::_getObject(
#		$session->{handle}, \@items, 0
#	    );
#	    $session->removeElement_P(
#		$class, $instance, $relation,
#		[ "OBJREF", "${class2}::${instance2}" ]
#	    );
#	}
#   }
#
#    return undef;

}



sub newHostObj {
    my $class = shift;
    my $self  = [];
    $self->[NAME] = shift;
    bless $self => $class;

}

# A method to get or set the NAME
sub name {
    my $self = shift;
    $self->[NAME] = shift if @_;
    $self->[NAME];
}

# A method that implements a "handle" multiplexer or  known as select
sub select
{
   my $timer = 0;
   my $rh=undef;
   ($rh, $timer) = @_;
   my @handList= ();
   my @rh = @{$rh};
   
   if ($timer > 0)
   {
      if( $timer < 1){
         throw "[12] Second parameter must an Integer >= 1.\n";
      }

      my $j=0;
      while($timer){
         $timer--;
         foreach $sh (@rh)
         {
             my $ret = $sh->{handle}->flowReadableNow();
             if( $ret > 0 )
             {
                 @handleList = (@handleList, $sh);
                 $j++;
             }
             if(($timer == 0 && $j == @rh) || ($j == @rh)){
               $j=0;
               $timer =0;
               last;
             }

         }
         sleep(1);
      }
   }
   else
   {
       my $i=0;
       foreach $sh (@rh)
       {
           my $ret = $sh->{handle}->flowReadableNow();
           if( $ret > 0 )
           {
               @handleList = (@handleList, $sh);
               $i++;
           }
       }
   }

   @ret = @handleList;
   @handleList = ( );
   return @ret;

}








=back

=head1 SEE ALSO

L<InCharge::intro>, L<InCharge::primitives>, L<InCharge::object>

=cut

1;

#### eof ####			    vim:ts=8:sw=4:sts=4:tw=79:fo=tcqrnol:noet:
