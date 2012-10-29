
#---------------------------------------------------------------------
# Wrapper around command line ssh for common remote login interface.
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
# RCS $Id: CLSSH.pm,v 1.9 2007/08/31 20:40:51 gurupv Exp $
# ---------------------------------------------------------------------

# Important!
# This entry must be in your '~/.ssh/config': StrictHostKeyChecking no

package SMARTS::CLI::Remote::CLSSH;

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

	my $remoteSession = SMARTS::CLI::Remote->new("ext", ...);

=head1 DESCRIPTION

B<SMARTS::CLI::Remote::CLSSH> implements C<SMARTS::CLI::Remote> over an
existing remote command line interaction utility, like OpenSSH.

It is transparently invoked by C<SMARTS::CLI::Remote>.

It derives from C<SMARTS::CLI::Remote::CommandLineDevice> which
implements a robust C<&cmd> method.


=cut

# 

@ISA = qw( SMARTS::CLI::Remote::CommandLineDevice );
use IO::Handle;
use IO::Pty;
use Net::Telnet;

# ---------------------------------------------------------------------
# Class definition and internal methods 


my $fields = {
	_kid		=> undef,
	_debug		=> undef,
	_prompt		=> undef,
	_params		=> undef,
	};

=pod

=head1 METHODS

=head2 C<&new>

The constructor internally called by C<SMARTS::CLI::Remote>. It passes
only the parameters defined in the C<Net::Telnet> package documentation
onwards to the C<Net::Telnet> constructor.

=cut

sub new {
	my ($that, $common, $host, $thelog, $scrubber, %params) = @_;
	print STDERR "+ command line ssh\n" if $common->{_debug};

	my %telnet_params;
	my @telnet_keys = (
		"binmode", "cmd_remove_mode", "dump_Log", "errmode", "fhopen", "host",
		"input_log", "input_record_separator", "option_log",
		"output_log", "output_record_separator",
		"port", "prompt", "telnetmode", "timeout"
		);

	$telnet_params{host} = $host;
	for my $key (@telnet_keys) {
		$telnet_params{$key} = $params{$key}
			if defined $params{$key};
		}

	my $prompt = '[\w().-]*\s*[\$\#\>\:\?]\s*';
	$prompt = $common->{prompt}
		if defined $common->{prompt};

	$prompt =~ s/HOST/\"$host\"/g;
	$telnet_params{prompt} = $prompt;

	$telnet_params{port} = 22	# for ssh
		unless defined $telnet_params{port};

	my $class = ref($that) || $that;
	my $self = SMARTS::CLI::Remote::CommandLineDevice->new(
				undef,
				defined $thelog,
				$thelog,
				$scrubber,
				$params{input_record_separator}
				);

	bless $self, $class;
	$self->{_debug} = $common->{_debug};
	$self->{_params} = \%telnet_params;

	return $self;
	}

sub _dochild {
	my ($self, $cmdstr) = @_;

	my ($pty, $tty, $tty_fd);

	$pty = IO::Pty->new
		or croak "Could not make pty: $!\n";

	unless ($self->{_kid} = fork) {
		croak "Could not fork: $!\n"
			unless defined $self->{_kid};

		POSIX::setsid or croak "Setsid failed: $!\n";

		$pty->make_slave_controlling_terminal;

		my $tty = $pty->slave;
		my $tty_fd = $tty->fileno;

		#STDIN->fdopen($tty, "<") or croak "STDIN: $!\n";
		#STDOUT->fdopen($tty, ">") or croak "STDOUT: $!\n";
		#STDERR->fdopen(\*STDOUT, ">") or croak "STDERR: $!\n";
		open STDIN, "<&$tty_fd" or croak "STDIN: $!\n";
		open STDOUT, ">&$tty_fd" or croak "STDOUT: $!\n";
		open STDERR, ">&STDOUT" or croak "STDERR: $!\n";

		close $pty;
		close $tty;
		$| = 1;

		my @args = split /\s+/,$cmdstr;
		eval { exec { $args[0] } @args; };

		croak "Could not exec [$args[0] : @args] $!\n";
		}

	return $pty;
	}

sub DESTROY { }

# 

# ---------------------------------------------------------------------
# Public methods 

=pod

=head2 C<&login($params, $user, $password)>

C<&login> takes an additional parameter as its first parameter, so that
the calling C<SMARTS::CLI::Remote> object can pass a reference to
itself. This is used as reference to the caller's hash table to fetch
parameters beyond those of the C<Net::Telnet> package, notably the
external command line utility to use for the connection, and arguments
to pass to it.

This implementation is designed to automatically handle password-less
login, id-less password login (configurable on many routers), and also
the first time query from OpenSSH's I<ssh> to "continue connecting?
yes/no" prompt.

To do so, a large number of keywords are included in the expected
response patterns. These keywords may be added to if more such keywords
are found, invariably thanks to be ingenuity of sysadmins to set up
login messages that can confuse any poor automatic tool into thinking it
failed to login, etc.

Returns the final response string from the device.

=cut

sub login {
	my ($self, $common, $user, $pw) = @_;

	croak "Already logged in\n"
		if defined $self->{session};

	carp "Remote host not defined, will try localhost\n"
		unless defined $self->{_params}{host};

	my $rhost = $self->{_params}{host};
	$rhost = "localhost" unless defined $rhost;

	my $cmdstr = $common->{ext_cmd};

	if (defined $common->{ext_options} && $common->{ext_options} ne "") {
		$common->{ext_options} =~ s/^\s+//;
		croak "External command options must begin with '-': ".$common->{ext_options}."\n"
			if $common->{ext_options} !~ /^[-]/;
		$cmdstr = $cmdstr." ".$common->{ext_options};
		}

	# Add switches to disable X11 and authentication agent forwarding
	$cmdstr = $cmdstr . " -x -a ";

	# Identify the user login
	$cmdstr = $cmdstr." -l ".$user
		if defined $user && $user ne "";

	$cmdstr = $cmdstr." ".$self->{_params}{host};

	my $prompt = $self->{_params}{prompt};
	$prompt =~ s/USER/$user/g;
	$prompt =~ s/\@/\\\@/g;

	print STDERR "+ cmdstr=$cmdstr, prompt=$prompt, pw=******\n"
		if $self->{_debug}; # password is in $pw 

	my $shell = Net::Telnet->new(
					Timeout	=> $self->{_params}{timeout},
					Binmode	=> $self->{_params}{binmode},
					Errmode	=> (defined
								$self->{_params}{errmode}
									? $self->{_params}{errmode}
									: 'return'),
					Prompt	=> $prompt,
					Input_log	=> $self->{_params}{input_log},
					Output_log	=> $self->{_params}{output_log},
					Dump_log	=> $self->{_params}{dump_log},
					);

	$shell->host($self->{_params}{host});
	$shell->port($self->{_params}{port});
	$shell->fhopen($self->_dochild($cmdstr));
	$shell->telnetmode(0);
	$shell->binmode(1);

	# use our command line device capability to simplify login
	$self->{session} = $shell;

	# build a prompt that supports the various possible responses from 
	# ssh logins...
	my $cmdprompt = 
		$prompt . 
		'[\w().-]*\s*[\$\#\>\:\?]\s*|' .
		'[Pp]assword|[Pp]assphrase|' .
		'continue connecting|denied|failed|rejected|timed|' .
		'(user|login|account)\s*(name|id|number)';

	my $response = $self->cmd("", $cmdprompt);
	print STDERR "GOT [$response]\n\n" if $self->{_debug};

	# ssh's cautionary barfs
	croak $rhost.": ".$response
		if $response =~ /(attack|nasty|eavesdropping)/i;

	# more generally
	croak $rhost.": ".$response
		if $response =~ /connection refused/i;

	# allow for ssh's cautionary response
	if ($response =~ /continue connecting/i) {
		print STDERR "+ ssh first time query, sending yes\n" if $self->{_debug};
		$response = $self->cmd("yes", $cmdprompt);
		print STDERR "GOT [$response]\n\n" if $self->{_debug};
		}

	# various forms of login prompts
	if ($response =~ /(user|login|account)\s*(name|id|number)*\s*:\s*$/i) {
		print STDERR "+ login prompt, sending id\n" if $self->{_debug};
		$response = $self->cmd($user, $cmdprompt);
		print STDERR "GOT [$response]\n\n" if $self->{_debug};
		}

	# various forms of password prompts
	if ($response =~ /(password|passphrase)/i) {
		print STDERR "+ password prompt, sending pw\n" if $self->{_debug};
		$response = $self->cmd($pw, $cmdprompt);
		print STDERR "GOT [$response]\n\n" if $self->{_debug};
		}

	# various forms of failure - feel free to add
	croak $rhost.": ".$response
		if $response =~ /(denied|failed|rejected|timed)/i;

        if ($response =~ /^\s*$/s) {
                print STDERR "GOT [*No Response*]\n\n" if $self->{_debug};
                croak "$rhost: unable to login\n";
        }

	return $response;
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

=head2 C<&print>

Simple wrapper for the corresponding C<Net::Telnet> method, which writes
to the remote device.

=cut

sub print {
	my ($self, $str) = @_;
	return $self->{session}->print($str);
	}

=pod

=head2 C<&logout>

Calls the super class C<&logout> handler and dispenses with the
C<Net::Telnet> handle.

=cut

sub logout {
	my ($self, $exitcmd) = @_;
	my $retval = $self->SUPER::logout($exitcmd);

	# force clean up to avoid unintuitive situations
	eval { kill 9, $self->{_kid}; };
	undef $self->{_kid};

	# bookkeeping
	delete $self->{session};
	undef $self->{session};

	return $retval;
	}

1; # 

__END__
# Documentation 

=head1 IMPORTANT

You may need this entry in your '~/.ssh/config': StrictHostKeyChecking no.

=head1 CAVEAT

Avoids the fixed buffer size and indefinite hang woes of C<Net::Telnet>,
at the risk of returning with incomplete data, the current limitation of
the parent class C<SMARTS::CLI::Remote::CommandLineDevice>.

The list of keywords to recognize login success or failure is hardcoded.
It would be nice to make it easier to configure from a configuration
file. The "obvious" choice of using environment variables may not work
because of possible limitations on total number or length of such
variables on various operating systems.


=head1 RELATED PACKAGES

C<Net::Telnet>,
C<IO::Pty>,
C<IO::Handle>,
C<SMARTS::CLI::Remote>,
C<SMARTS::CLI::Remote::CommandLineDevice>.

This package is part of C<SMARTS::CLI::Remote>.

=cut
