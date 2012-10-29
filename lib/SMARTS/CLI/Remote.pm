# ---------------------------------------------------------------------
# Common API for remote login and command execution.
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
# RCS $Id: Remote.pm,v 1.5 2007/08/31 20:41:27 gurupv Exp $
# ---------------------------------------------------------------------
package SMARTS::CLI::Remote;

# Packet interface and settings 

=head1 NAME

B<SMARTS::CLI::Remote>
Unified command line interaction interface.

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

@EXPORT_OK = qw(
		);

=pod

=head1 SYNOPSIS

	use SMARTS::CLI::Remote;

	my $ext_cmd  = "/usr/bin/ssh" ;	# or "/usr/bin/telnet" or undef
	my $ext_args = "";			# e.g. "-v"
	my $port = undef;			# undef=default. use 23 for telnet

	my $climethod  = "ext";
	#my $climethod = "Net::SSH::Perl";
	#my $climethod = "Net::Telnet";

	my $remoteHostName;			# to connect to
	my $clihandle;				# file handle
	my $login_timeout = 10;
	my $prompt = '[\$\#\>\:]';		# pattern for remote command prompt

	my $sshVersion = 2;					# protocol level
	my $scrubber = sub { s/^M//g; };	# response filter example

	my $remoteSession = SMARTS::CLI::Remote->new(
			$climethod,
			$remoteHostName,
			$clihandle,
			$scrubber,
			(
				_debug	=> undef,	# 1 to enable trace to STDERR
				timeout	=> $login_timeout,
				prompt		=> $prompt,
				protocol	=> $sshVersion,
				port		=> $port,
				ext_cmd		=> $ext_cmd,
				ext_args	=> $ext_args,

				# uncomment for debugging
				#input_log	=> "/tmp/".$remoteHostName.".input.log",
				#output_log	=> "/tmp/".$remoteHostName.".output.log",
				#dump_log	=> "/tmp/".$remoteHostName.".dump.log",
			)
		);

	my $login, $passwd, $cmd;

	$remoteSession->login($login, $passwd);
	$remoteSession->print("\n");		# to remote host for extra prompt
	$remoteSession->setReadTimeout(3);	# in seconds
	$remoteSession->cmd($cmd);
	$remoteSession->logout;



=head1 DESCRIPTION

The B<SMARTS::CLI::Remote> module provides a platform-independent common
interface wrapper for the use of I<telnet>, I<ssh> etc. command line
interaction methods.

Probe, adapter, monitoring or other scripts can be written independently
of which method, e.g. Telnet or SSH, and how, e.g. using C<Net::Telnet>
or I</usr/bin/telnet>, is available or preferred for use in a customer
environment, by the use of this package.

The specific method can be then configured centrally as environment
variables set in I<sm_perl.options> for Perl-specific use, or in a
product-specific configuration file or location, etc.

This package is meant to be a thin wrapper providing a small but robust
set of commands for CLI data gathering. As such, some features of the
individual remote login interfaces internally used by this wrapper are
intentionally not reflected in the common interface. This includes the
protocol configuration that can be supplied as the second argument to
C<< Net::SSH::Perl->new() >>, since this configuration for a command line
I<ssh> program can be picked up only from C<$HOME/.ssh> or
C</etc/ssh/ssh_config>.

This package is really nothing more than a common constructor that
invokes the right backend constructor. The command methods are really
implemented in the backends. This two-level construction was necessary
to separate the loading of the backend's dependencies, which would
otherwise need to be available and installed on all platforms even if
never used.

=cut

# 

use IO::Handle;

# ---------------------------------------------------------------------
# Class definition and internal methods 

my $fields = {
	_ext		=> undef,
	_debug		=> 1,
	shell		=> "sh",
	prompt		=> '[\$\#\>\:]',
	ext_cmd		=> "ssh",
	ext_args	=> undef,
	};

sub new {
	my ($that, $method, $host, $thelog, $scrubber, %params) = @_;
	my $class = ref($that) || $that;
	my $self = { %$fields };

	bless $self, $class;

	for my $key (keys %params) {
		if ($key =~ /[A-Z]/) {
			my $newkey = lc($key);
			$params{$newkey} = $params{$key};
			}
		}

	for my $key (keys %$fields) {
		$self->{$key} = $params{$key}
		    if defined $params{$key};
	}

	my $pkg;
	$pkg = qw(SMARTS::CLI::Remote::PerlSSH) if $method eq "Net::SSH::Perl";
	$pkg = qw(SMARTS::CLI::Remote::Telnet) if $method eq "Net::Telnet";
	$pkg = qw(SMARTS::CLI::Remote::CLSSH) if $method eq "ext";

	croak "Requested remote-CLI [$method] not defined or supported\n"
		unless defined $pkg;

	eval "require $pkg" or
		croak "Package [$pkg] failed to load: $!\n".
		"\@INC = @INC";

	$self->{_ext} = $pkg->new($self, $host, $thelog, $scrubber, %params);

	return $self;
	};

sub DESTROY { }


=pod

=head1 METHODS

=head2 C<&new($$$$)>

Constructs a remote session object. This object will invoke an external
command like I</usr/bin/ssh> or I</usr/bin/telnet>, or the Perl modules
C<Net::Telnet> or C<Net::SSH::Perl>, depending on the first argument,
and encapsulates all uses of this invoked mechanism. Currently supported
values for the first argument are (all are Perl string constants):

=over 25

=item *
"ext"              - use external command C<$ext_cmd> with C<$ext_args>

=item *
"Net::Telnet"      - load and use the C<Net::Telnet Perl> package

=item *
"Net::SSH::Perl"   - load and use the C<Net::SSH::Perl> package

=back

The "ext" method uses C<Net::Telnet>, C<IO::Pty> and C<IO::Handle>.
Thus, at least one of C<Net::SSH::Perl> or C<Net::Telnet> packages must
be available for the package to work at all.  C<IO::Pty> and
C<IO::Handle> must be installed as well for the "ext" method. Any other
value of the first argument will cause an exception.

Second argument is the remote hostname or IP address. This will be used
directly by the invoked mechanism to establish a connection and a
subsequent login session.

Third argument is an output file handle. If defined, all traffic will be
logged to this file. The debug logs arguments are another way to collect
this data.

The last argument is expected to be a hash table of parameters for the
invoked mechanism. A few defaults are defined purely for reference:

=over 25

=item *
{ext_cmd}="ssh"        - so that the first I<ssh> in the user PATH environment variable will get picked up

=item *
{ext_args}=undef       - a placeholder

=item *
{prompt}='[\$\#\>]'    - successful login indicator

=item *
{shell}="sh"           - just in case

=back

Any key-value pair supplied in this argument table will be passed
along as is, and may override these defaults.

If C<Net::Telnet> is used, which is the default case, the following
debug log parameters can be used as alternative or in addition to
the handle argument.

=over 12

=item *
input_log	=> "/tmp/".$remoteHostName.".input.log",

=item *
output_log	=> "/tmp/".$remoteHostName.".output.log",

=item *
dump_log	=> "/tmp/".$remoteHostName.".dump.log",

=back

=cut

# 

# ---------------------------------------------------------------------
# Public methods 

my $__invalid = "Invalid remote handle\n";

#sub verbose { $__verbose = 1; }

=pod

=head2 C<&login($user, $pw)>

The C<&login> method of the invoked mechanism is called.

Returned value depends on the invoked mechanism. In case of "ext",
the the final response string received from the device is returned. The
value depends on the C<errmode()> setting in case of C<Net::Telnet> -
please refer to the C<Net::Telnet> documentation. C<Net::SSH::Perl>
package does not document a return value.

=cut

sub login {
	my ($self, $user, $pw) = @_;
	croak $__invalid unless defined $self->{_ext};
	my $retval;
	eval {
		$retval = $self->{_ext}->login($self, $user, $pw);
	};
	croak $@ if $@;
	return $retval;
	}


=pod

=head2 C<&cmd($string[,$pattern])>

The C<&cmd> method of the invoked mechanism is called, but with
additional wrapping to overcome limitations of and differences between
C<Net::Telnet> and C<Net::SSH::Perl> packages.

The limitation in C<Net::Telnet> is the fixed size buffering. This
frequently causes its C<&cmd> method to hang, I<indefinitely>, if the
remote host happens to spews out more than the buffer limit, because
timeout is disabled by the package design (!) and the method ends up waiting
for a prompt for which its buffer has no more space!

For C<Net::SSH::Perl>, we wrap its C<&cmd> method mainly to copy the
data to the output file handle C<$clihandle>. Had C<Net::SSH::Perl>
provided the C<input_log>, C<output_log> and C<dump_log> options like
C<Net::Telnet>, this wrapping could have been avoided, along with the
separate file handle argument to the constructor.

The pattern argument signals C<SMARTS::CLI::Remote::CommandLineDevice>'s
C<&cmd> method to continue reading until the pattern is matched. It
is silently ignored by the wrapper for C<Net::SSH::Perl>.

Note that C<Net::Telnet> returns 1 in the scalar context on success,
whereas C<SMARTS::CLI::Remote::CommandLineDevice> returns the actual
string buffer and overrides C<Net::Telnet->cmd>. The present wrapper on
C<Net::SSH::Perl> also returns the actual string.

=cut

sub cmd {
	my ($self, $str, $pattern) = @_;
	croak $__invalid unless defined $self->{_ext};
	my @lines;
	eval {
		@lines = $self->{_ext}->cmd($str, $pattern);
	};
	croak $@ if $@;
	return wantarray ? @lines : "@lines";
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

This only works with C<Net::Telnet>, i.e. for actual I<telnet> using
the C<Net::Telnet> package or an external command.

=cut

sub setReadTimeout {
	my ($self, $rtmout) = @_;
	croak $__invalid unless defined $self->{_ext};
	# not eval-wrapping as it only carps
	return $self->{_ext}->setReadTimeout($rtmout);
	}

=pod

=head2 C<&readTimedOut>

Check if the previous read timed out on the underlying command line device.

This only works with C<Net::Telnet>, i.e. for actual I<telnet> using
the C<Net::Telnet> package or an external command.

=cut

sub readTimedOut {
	my $self = shift;
	return $self->{session}->{timedout};
	}

=pod

=head2 C<&print($string)>

The C<&print> method of the invoked mechanism is called.

This only works with C<Net::Telnet>, i.e. for actual I<telnet> using
the C<Net::Telnet> package or an external command.

=cut

sub print {
	my ($self, $str) = @_;
	croak $__invalid unless defined $self->{_ext};
	eval {
		$self->{_ext}->print($str);
	};
	croak $@ if $@;
	}

=pod

=head2 C<&logout($exitcmd)>

The C<&logout> method of the invoked mechanism is called. The purpose of
this is to supply the session termination command appropriate to the
backend protocol. The reason is that different backend protocols have
established different termination commands - I<ssh> is typically
terminated by the login shell C<exit> command, while I<ftp> requires
C<quit> instead of C<exit>. The remote host response if any is returned.

This only works at present when using C<Net::Telnet>, i.e. for actual
I<telnet> using the C<Net::Telnet> package or an external command.

B<NOTE> Calling C<&logout> is mandatory for proper cleanup of the
backend handles.

=cut

sub logout {
	my ($self, $exitcmd) = @_;
	croak $__invalid unless defined $self->{_ext};
	return $self->{_ext}->logout($exitcmd);
	}

1; # 

__END__
# ---------------------------------------------------------------------
# Documentation 

=head1 LIMITATIONS


1.
The package is an encapsulation of a very limited subset of methods
provided by C<Net::Telnet> and C<Net::SSH::Perl> identified as needed
and sufficient for automated discovery and monitoring purposes. It might
be desirable to integrate other similar packages in the future, but it
is possible to run into difficulty implementing the present set of
commands over them.

The native methods of C<Net::Telnet> and C<Net::SSH::Perl> can still be
accessed via C<< ->{_ext} >>, and could lead to problems.


2.
C<IO::Pty> is not available on some platforms, e.g. Windows, and would
limit the use of command line I<ssh> like PuTTY. C<IO::Pty> is available
under Cygwin (see C<http://www.cygwin.com>) but using this would require
installing Cygwin Perl.


3.
All of the methods use the login handshake built-in in C<Net::Telnet>
and C<Net::SSH::Perl>, or provided by C<SMARTS::CLI::Remote::CLSSH>. It
turns out that C<Net::Telnet> doesn't handle password security without
a user id prompt, as can be configured on a Cisco IOS router. Only
C<SMARTS::CLI::Remote::CLSSH> has been generalized to handle id-less
password login and password-less login. As such, it may be necessary to
use "ext" even when C<Net::SSH::Perl> is available.


4.
The two-level design makes calling C<&logout> necessary for cleanup.


=head1 FILES

C<$SM_SITEMOD/local/bin/system/sm_perl.options> defines 
environment variables for launching the installed Perl interpreter
with C<@INC> path correctly initialized to load this and other EMC
Smarts Perl libraries.


=head1 RELATED PACKAGES

C<Net::SSH::Perl>,
C<Net::Telnet>,
C<IO::Pty>,
C<IO::Handle>,
C<SMARTS::CLI::Remote::CommandLineInterface>,
C<SMARTS::CLI::Remote::Telnet>,
C<SMARTS::CLI::Remote::CLSSH>,
C<SMARTS::CLI::Remote::PerlSSH>.


=cut
