# ---------------------------------------------------------------------
# Wrapper around command line telnet for common remote login interface.
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
# RCS $Id: Telnet.pm,v 1.4 2007/08/31 20:41:28 gurupv Exp $
# ---------------------------------------------------------------------
package SMARTS::CLI::Remote::Telnet;

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
	   );

=pod

=head1 SYNOPSIS

	my $remoteSession = SMARTS::CLI::Remote->new("Net::Telnet", ...);

=head1 DESCRIPTION

B<SMARTS::CLI::Remote::Telnet> implements C<SMARTS::CLI::Remote> over
C<Net::Telnet>.

It derives from C<SMARTS::CLI::Remote::CommandLineDevice> which
implements a robust C<&cmd> method.

=cut

# 

@ISA = qw( SMARTS::CLI::Remote::CommandLineDevice );

use Net::Telnet;

# ---------------------------------------------------------------------
# Class definition and internal methods 

=pod

=head1 METHODS

=head2 C<&new>

The constructor internally called by C<SMARTS::CLI::Remote>. It passes
only the parameters defined in the C<Net::Telnet> package documentation
to the C<Net::Telnet> constructor.

=cut

sub new {
	my ($that, $common, $host, $thelog, $scrubber, %params) = @_;
	print STDERR "+ telnet\n" if $common->{_debug};

	my %telnet_params;
	my @telnet_keys = (
		"binmode", "cmd_remove_mode", "dump_Log", "errmode", "fhopen", "host",
		"input_log", "input_record_separator", "option_log",
		"output_log", "output_record_separator",
		"port", "prompt", "telnetmode", "timeout"
		);

	for my $key (@telnet_keys) {
		#print "# $key -> $params{$key}\n"; # if $common->{_debug};
		$telnet_params{$key} = $params{$key}
			if defined $params{$key};
		}

	$telnet_params{host} = $host;
	$telnet_params{prompt} = "/password|logout|$common->{prompt}/i"
		if defined $common->{prompt};

	my $session = Net::Telnet->new(%telnet_params);
	my $class = ref($that) || $that;

	# build the prompt string for CommandLineDevice. Append the
	# string for handling logout and password prompts
	my $cldprompt = $common->{prompt};
	$cldprompt = $params{prompt} if defined $params{prompt};
	$cldprompt .= "|logout";

	my $self = SMARTS::CLI::Remote::CommandLineDevice->new(
				$session,
				defined $thelog,
				$thelog,
				$scrubber,
				$params{input_record_separator},
			    $params{timeout},
			    $cldprompt
				);

	bless $self, $class;
	$self->{_debug} = $common->{_debug};	# for debug use if needed

	return $self;
	}

sub DESTROY { }

# 

# ---------------------------------------------------------------------
# Public methods 

=pod

=head2 C<&login>, C<&print>

Both are simple wrappers for the corresponding C<Net::Telnet> methods.

C<&login> takes an additional parameter as its first parameter, so that
the calling C<SMARTS::CLI::Remote> object can pass a reference to
itself. This caller reference is ignored in this package.

=cut

sub login {
	my ($self, $common, $user, $pw) = @_;
	print STDERR "+ telnet login\n" if $common->{_debug};

	croak "Not connected\n"
		unless defined $self->{session};

        croak "Must have user or pw defined\n"
		if ($pw eq "") && ($user eq "");

	# Check if this is a password only type login.
	# Have to do that manually. Taken mostly from login routine in	
	# Net::Telnet as an example
	if ($user eq "") {
		my $match;
		my $prematch;
		
		print STDERR "+ telnet login pw only\n" if $common->{_debug};
		# Check for a password prompt
		$self->{session}->waitfor(Match => '/password[: ]*$/i',
					  Errmode => "return")
		    or do {
			return $self->{session}->error("eof read waiting for password") if $self->{session}->eof;;
			return $self->{session}->error("timeout waiting for password");
		    };
		
		# Evidently required sleep on some hosts
		sleep(1);

		# Now push the password out
		$self->{session}->put(String => $pw . "\n",
				      Errmode => "return")
		    or do return $self->{session}->error("login disconnected");

		# Wait for either a new login/password prompt or a good prompt
		($prematch, $match) = 
		    $self->{session}->waitfor(Match => '/password[: ]*$/i', 
					      Match => '/login[: ]*$/i', 
					      Match => '/username[: ]*$/i', 
					      Match => $self->{session}->prompt(),
					      Errmode => "return")
		    or do {
			return $self->{session}->error("eof read waiting for prompt") if $self->{session}->eof;;
                        return $self->{session}->error("timeout waiting for prompt");
                    };
		# Error out if we got a login prompt (this isn't pw only)
		return $self->{session}->error("login failed: not password only") if $match =~ /login[: ]*$/i or $match =~ /username[: ]*$/i;

		# Error out if the password wasn't liked
		return $self->{session}->error("login failed: incorrect password") if $match =~ /password[: ]*$/i;

		# Otherwise save the prompt string and return
		$self->{session}->last_prompt($match);
		return 1;
	} elsif ($pw eq "") {
		my $match;
		my $prematch;
		
		print STDERR "+ telnet login user only\n" if $common->{_debug};
		# Check for a login prompt
		$self->{session}->waitfor(Match => '/login[: ]*$/i',
					  Match => '/username[: ]*$/i',
					  Errmode => "return")
		    or do {
			return $self->{session}->error("eof read waiting for login prompt") if $self->{session}->eof;;
			return $self->{session}->error("timeout waiting for login prompt");
		    };
		
		# Evidently required sleep on some hosts
		sleep(1);

		# Now push the username out
		$self->{session}->put(String => $user . "\n",
				      Errmode => "return")
		    or do return $self->{session}->error("login disconnected");

		# Wait for either a new login/password prompt or a good prompt
		($prematch, $match) = 
		    $self->{session}->waitfor(Match => '/password[: ]*$/i', 
					      Match => '/login[: ]*$/i', 
					      Match => '/username[: ]*$/i', 
					      Match => $self->{session}->prompt(),
					      Errmode => "return")
		    or do {
			return $self->{session}->error("eof read waiting for prompt") if $self->{session}->eof;;
                        return $self->{session}->error("timeout waiting for prompt");
                    };
		# Error out if we got a password prompt (this isn't user only)
		return $self->{session}->error("login failed: requires password") if $match =~ /password[: ]*$/i;

		# Error out if the username wasn't liked
		return $self->{session}->error("login failed: user invalid?") if $match =~ /login[: ]*$/i or $match =~ /username[: ]*$/i;

		# Otherwise save the prompt string and return
		$self->{session}->last_prompt($match);
		return 1;
        } else {
		return $self->{session}->login($user, $pw);
	}
}

sub print {
	my ($self, $str) = @_;
	return $self->{session}->print($str);
}

=pod

=head2 C<&setReadTimeout>

Sets read timeout on the underlying command line device to the argument
value, and returns the old value, so it can be restored later.

If no argument given, it simply returns the old value. If the argument
is negative, the timeout is set to undefined, so that a subsequent read 
can wait indefinitely for a matching prompt. Note that if a prompt
pattern is not specified, the read will not block at all, regardless of
the timeout setting.

=cut

sub setReadTimeout {
	my ($self, $rtmout) = @_;
	my $oldvalue = $self->{rtmout};

	return $oldvalue unless defined $rtmout;

	$self->{rtmout} = $rtmout
		if $rtmout >= 0;

	undef $self->{rtmout}
		if $rtmout < 0;

	return $oldvalue;

	}

=pod

=head2 C<&readTimedOut>

Check if the previous read timed out on the underlying command line device.

=cut

sub readTimedOut {
	my $self = shift;
	return $self->{timedout};
	}

=pod

=head2 C<&cmd>

Inherited from the robust C<SMARTS::CLI::Remote::CommandLineDevice>,
in place of C<Net::Telnet>'s clunky implementation.

=head2 C<&logout>

Calls the super class C<&logout> handler and dispenses with the
C<Net::Telnet> handle.

=cut

sub logout {
	my ($self, $exitcmd) = @_;
	my $retval = $self->SUPER::logout($exitcmd);

	# clean up to avoid unintuitive situations
	delete $self->{session};
	undef $self->{session};

	return $retval;
	}

1; # 

__END__
# Documentation 

=head1 CAVEAT

Avoids the fixed buffer size and indefinite hang woes of C<Net::Telnet>,
at the risk of returning with incomplete data, the current limitation of
the parent class C<SMARTS::CLI::Remote::CommandLineDevice>.


=head1 RELATED PACKAGES

C<Net::Telnet>,
C<SMARTS::CLI::Remote>,
C<SMARTS::CLI::Remote::CommandLineDevice>.

This package is part of C<SMARTS::CLI::Remote>.

=cut
