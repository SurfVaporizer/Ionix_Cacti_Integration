# ---------------------------------------------------------------------
# Unified support for dynamically resizing buffer and data logging
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
# RCS $Id: CommandLineDevice.pm,v 1.2 2007/08/31 20:41:28 gurupv Exp $
# ---------------------------------------------------------------------

package SMARTS::CLI::Remote::CommandLineDevice;	

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

our $VERSION = "1.2";

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

	$session = Net::Telnet->new(...);
	$clidata = open($filename);
	$scrubber = sub { $self->{buffer} =~ s/^G//g; }; // etc.

	$clisession = SMARTS::CLI::Remote::CommandLineDevice->new(
					$session,
					TRUE,
					$clidata,
					$scrubber
					);

	my @output = $clisession->cmd("ps -ef");
	#my @output = $clisession->cmd("ps -ef", '/[\$\#\s*]$/');
	$clisession->logout;


=head1 DESCRIPTION

B<SMARTS::CLI::Remote::CommandLineDevice> implements
a robust C<&cmd> method with variable length buffering.

=cut

# 

use FileHandle;

# OO interface

my $__fields = {
	session	=> undef,		# logged in or simulated
	logging	=> undef,		# boolean - whether to log the interaction
	thelog	=> undef,		# open file or stream handle
	buffer	=> undef,		# medicinal -- "for internal use only"
	scrub	=> undef,		# callback filter to clean received data
	rtmout	=> 30,			# a default read timeout
	pattern	=> undef,		# for alternative return from read
	timedout => undef,		# if we timedout on previous read
	irs		=> undef,		# input_record_separator for parsing
	};

=pod

=head1 METHODS

=head2 C<&new>

The constructor internally called by both C<SMARTS::CLI::Remote::Telnet>
and C<SMARTS::CLI::Remote::CLSSH>.

The first argument must be a session handle, say from C<Net::Telnet>,
which supports C<&eof>, C<&print> and C<&get> methods, the C<&get>
method with a timeout option.

=cut

sub new($$$$$) {
	my ($that, $session, $logging, $thelog, $scrub, $irs, $rtmout, $pattern) = @_;

	my $class = ref($that) || $that;
	my $self = { %$__fields };

	bless $self, $class;
	$self->{session} = $session;
	$self->{logging} = $logging;
	$self->{thelog} = $thelog;
	$self->{scrub}  = $scrub;
	$self->{irs}	= "\n";
	$self->{timedout} = 0;

	$self->{irs} = $irs
		if defined $irs;

	$self->{rtmout} = $rtmout
		if defined $rtmout;

	$self->{scrub} = sub {}
		unless defined $scrub;

	$self->{pattern} = $pattern
		if defined $pattern;

	return $self;
	}

sub DESTROY { }

# 

# methods 

sub __read {
	my ($self, $readpattern) = @_;
	my $session = $self->{session};
	my $startedat = time;

	$readpattern = $self->{pattern}
	    unless defined $readpattern;

	$self->{timedout} = 0;
	while (1) {
		my $more;

		# a 1 ms read to make this nonblocking
		eval { $more = $session->get(Timeout => 0.001); };

		if (defined $more && $more ne "") {
			$self->{buffer} .= $more;
			# reset timeout since we got something
			$startedat = time;
			next;
			}

		# no more available data
		# return if we were given no reason to wait
		last unless defined $readpattern;

		# or if we did get the expected output
		last if $self->{buffer} =~ $readpattern;

		# or if we were told a timeout and it's time
		if (defined $self->{rtmout} && (time - $startedat > $self->{rtmout})) {
			$self->{timedout} = 1;
			last;
		}
	}
}


sub __split {
	my ($self, $buffer) = @_;
	my ($firstpos, $lastpos, $rs_len);
	my @lines;

	# split buffer into lines preserving the record separator
	$firstpos = 0;
	$rs_len = length $self->{irs};
	while (($lastpos = index($buffer, $self->{irs}, $firstpos)) > -1) {
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

=pod

=head2 C<&cmd($str[,$pattern])>

A robust implementation of the C<&cmd> method that
(a) will not run out of buffer space in worst case (unless the calling
    process has as such exhausted its virtual address space,
(b) does not require worst case buffer allocation for mostly small data,
(c) will not hang long after the remote host has disconnected.

These defects exist in the C<Net::Telnet>'s current implementation of
C<&cmd> and have been traced to the combination of disabling timeout,
using a fixed length buffer, and waiting to recognize a prompt or other
terminating C<$pattern>.

This implementation loops on an internal C<&__read> method that loops on
a nonblocking internal C<&__read> method. It checks for I<eof>, and does
a nonblock read using C<&get> with a small but reasonable timeout (for
today's computers), to essentially grab the output of a single I<read>
system call. The output is appended to a variable length buffer that
grows with each byte read, so that an expected terminating C<$pattern>
will (almost) always be accommodated.

As getting the prompt pattern right, as well as the likelihood that the
remote device can often be more sluggish than acceptable, a separate,
larger timeout, in seconds, can be set, either in the constructor or
subsequently as the parameter C<&rtmout> in this object's hash table,
to ensure timely return.

=cut

sub cmd {
	my ($self, $str, $pattern) = @_;

	my $session = $self->{session};

	my $ptrn = $self->{pattern};
	$ptrn = $pattern
		if defined $pattern;

	croak "Not connected\n"
		unless defined $self->{session};

	$self->{buffer} = "";
	$session->print($str) if defined $str;

	$self->__read($ptrn);
	&{$self->{scrub}}(\$self->{buffer});
	$self->{thelog}->print($self->{buffer}) if $self->{logging};

	return wantarray ? $self->__split($self->{buffer}) : $self->{buffer};
	}

sub logout {
	my ($self, $exitcmd) = @_;
	$exitcmd = "exit" unless defined $exitcmd;
	return $self->cmd($exitcmd);
	}

# 

1; #  -- package

__END__
# Documentation 

=head1 CAVEAT

Currently implemented and tested to be robust with high volume, high
speed data. Will likely still return with incomplete response from slow
or overloaded, unresponsive devices, since it is impossible to predict how
much time a given device might need to respond on a particular read.

=head1 RELATED PACKAGES

C<Net::Telnet>,
C<SMARTS::CLI::Remote>.

This package is part of C<SMARTS::CLI::Remote>.

=cut

# 
