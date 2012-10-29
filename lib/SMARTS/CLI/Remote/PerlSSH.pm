# ---------------------------------------------------------------------
# Wrapper around Net::SSH::Perl for common remote login interface.
#
# Copyright 2007 by EMC Corporation ("EMC").
# All rights reserved.
#
# UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The copyright
# notice above does not evidence any actual or intended publication of this
# software.  Disclosure and dissemination are pursuant to separate
# agreements.  Unauthorized use, distribution or dissemination are strictly
# prohibited.
#
# RCS $Id: PerlSSH.pm,v 1.4 2007/08/31 20:41:28 gurupv Exp $
# ---------------------------------------------------------------------
package SMARTS::CLI::Remote::PerlSSH;

# Packet interface and settings 

=head1 NAME

SMARTS::CLI::Remote::Telnet
Implementation of SMARTS::CLI::Remote over Net::Telnet

=head2 COPYRIGHT

Copyright 2005-2007 by EMC Corporation ("EMC").
All rights reserved.

UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The copyright
notice above does not evidence any actual or intended publication of
this software.  Disclosure and dissemination are pursuant to separate
agreements.  Unauthorized use, distribution or dissemination are
strictly prohibited.

=cut

use strict;
use warnings;
use 5.006_001;

our $VERSION = '1.2';

use Carp qw(croak carp);
use Exporter;
use Config;

use vars qw( 
		@ISA 
		@EXPORT
		@EXPORT_OK 
	   );
	   
@ISA = ('Exporter');

@EXPORT = qw(
             );

=pod

=head1 SYNOPSIS


	my $remoteSession = SMARTS::CLI::Remote->new("Net::SSH::Perl", ...);
	$remoteSession->{_exitstatus}
	$remoteSession->{_errlines}


=head1 DESCRIPTION

B<SMARTS::CLI::Remote::PerlSSH> implements C<SMARTS::CLI::Remote> over
C<Net::SSH::Perl>.

It is transparently invoked by C<SMARTS::CLI::Remote>.

It uses the native C<&cmd> method of C<Net::SSH::Perl>.

=cut

# 

use Net::SSH::Perl;

# ---------------------------------------------------------------------
# Class definition and internal methods 


my $fields = {
	_ssh		=> undef,
	_debug		=> undef,
	_thelog		=> undef,		# file or stream handle
	_prompt		=> undef,
	_exitstatus	=> undef,
	_errlines	=> undef,
	_irs		=> undef,		# input record separator
	};

=pod

=head1 METHODS

=head2 C<&new>

The constructor internally called by C<SMARTS::CLI::Remote>. It passes
only the parameters defined in the C<Net::SSH::Perl> package
documentation onwards to the C<Net::SSH::Perl> constructor.

=cut

sub new {
	my ($that, $common, $host, $thelog, $scrubber, %params) = @_;
	print STDERR "+ perl ssh lib\n" if $common->{_debug};

	my %ssh_params;
	my @ssh_keys = (
		"debug",
		"protocol", "cipher", "ciphers", "port", "options",
		"privileged", "identity_files", "compression", "compression_level",
		# These other options are legal but should not be used:
		# "interactive", "use_pty",
		);

	for my $key (@ssh_keys) {
		$ssh_params{$key} = $params{$key}
			if defined $params{$key};
		}

	$ssh_params{host} = $host;
	$ssh_params{prompt} = "/password|logout|$common->{prompt}/i"
		if defined $common->{prompt};

	my $session = Net::SSH::Perl->new($host, %ssh_params);
	my $class = ref($that) || $that;

	# build the prompt string for CommandLineDevice. Append the
	# string for handling logout and password prompts
	my $cldprompt = $common->{prompt};
	$cldprompt = $params{prompt} if defined $params{prompt};
	$cldprompt .= "|logout";

	my $self = { %$fields };

	bless $self, $class;
	$self->{_debug} = $common->{_debug};
	$self->{_ssh} = $session;
	$self->{_irs} = "\n";
	$self->{prompt} = $cldprompt;

	$self->{_irs} = $params{input_record_separator}
		if defined $params{input_record_separator};

	return $self;
	}

sub DESTROY { }

sub __connected {
	my $self = shift;
	croak "Not connected\n"
		unless defined $self->{_ssh};
	}

sub __split {
	my ($self, $buffer) = @_;
	my ($firstpos, $lastpos, $rs_len);
	my @lines;

	# split buffer into lines preserving the record separator
	$firstpos = 0;
	$rs_len = length $self->{_irs};
        while (($lastpos = index($buffer, $self->{_irs}, $firstpos)) > -1) {
		push @lines, substr($buffer, $firstpos, $lastpos - $firstpos + $rs_len);
		$firstpos = $lastpos + $rs_len;
		}

	if ($firstpos < length $buffer) {
		push @lines, substr($buffer, $firstpos);
		}

	# ensure TRUE return in list context
	unless (@lines) {
		@lines = ("");
		}

	return @lines;
	}

# 

# ---------------------------------------------------------------------
# Public methods 

=pod

=head2 C<&login>, C<&print>

Simple wrappers for the corresponding C<Net::SSH::Perl> methods.

C<&login> takes an additional parameter as its first parameter, so that
the calling C<SMARTS::CLI::Remote> object can pass a reference to
itself. This caller reference is ignored in this package.

=cut

sub login {
	my ($self, $common, $user, $pw) = @_;

	$self->__connected;
	$self->{_ssh}->login($user, $pw);
	}

sub print {
	my ($self, $str) = @_;
	return $self->{_ssh}->print($str);
	}


=pod

=head2 C<&cmd>

Wrapper on the C<Net::SSH::Perl> C<&cmd> method, providing the
C<Net::Telnet>, C<SMARTS::CLI::Remote> semantics of returning 
an array of lines only.

The stderr output and exit status from the remote command, returned by
C<Net::SSH::Perl>'s C<&cmd>, are saved in C<_errlines> and
C<_exitstatus> fields, respectively.


=cut

sub cmd {
	my ($self, $str) = @_;

	$self->__connected;

	print STDERR "+ $str\n" if $self->{_debug};

	my ($out, $err, $exit) = $self->{_ssh}->cmd($str);
	$self->{_exitstatus} = $exit;
	$self->{_errlines} = $self->__split($err);
	$self->{_thelog}->print($out) if defined $self->{_thelog};

	return wantarray ? $self->__split($out) : $out;
	}


=pod

=head2 C<&setReadTimeout>

Sets read timeout on the underlying command line device.
A wrapper provided for API compatibility, since the Net::SSH::Perl module
doesn't have this functionality.

=cut

sub setReadTimeout {
	my ($self, $rtmout) = @_;
	carp("Read timeout not supported");
	}

=pod

=head2 C<&readTimedOut>

Check if the previous read timed out on the underlying command line device.
A wrapper provided for API compatibility, since the Net::SSH::Perl module
doesn't have this functionality.

=cut

sub readTimedOut {
	my $self = shift;
	carp("Read timeout not supported");
	}

=pod

=head2 C<&logout>

Calls the super class C<&logout> handler and dispenses with the
C<Net::SSH::Perl> handle.

=cut

sub logout {
	my ($self, $exitcmd) = @_;
	$exitcmd = "exit" unless defined $exitcmd;
	my $retval = $self->cmd($exitcmd);

	# clean up to avoid unintuitive situations
	delete $self->{_ssh};
	undef $self->{_ssh};

	return $retval;
	}

1; # 

__END__
# Documentation 

=head1 CAVEAT

This package uses the native C<Net::SSH::Perl> C<&login> method which
does not handle id-less passwords.


=head1 RELATED PACKAGES

C<Net::SSH::Perl>,
C<SMARTS::CLI::Remote>.

This package is part of C<SMARTS::CLI::Remote>.


=cut

# 
