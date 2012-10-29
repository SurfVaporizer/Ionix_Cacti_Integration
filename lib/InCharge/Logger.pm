# ---------------------------------------------------------------------
#
# InCharge support for monitoring using Perl: Monitored Object
#
# Copyright 1996-2005 by EMC Corporation ("EMC").
# All rights reserved.
# 
# UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
# copyright notice above does not evidence any actual or intended
# publication of this software.  Disclosure and dissemination are
# pursuant to separate agreements. Unauthorized use, distribution or
# dissemination are strictly prohibited.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-probe/perl/Logger.pm#1 $
#
# ---------------------------------------------------------------------
# Packet interface and settings {{{

package InCharge::Logger;

use strict;
use warnings;
use 5.006_001;
use IO::Handle;

our $VERSION = '1.0';

use Carp qw(croak);
use Exporter;
#use Fcntl qw(:DEFAULT :flock);

# }}}

# ---------------------------------------------------------------------
# Class definition and methods {{{

my @__mnames	= ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
		   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
my $__logdir	= "$ENV{SM_HOME}/local/logs";
my $__logext	= "log";
my $__name	= $0;
$__name 	=~ s/.+[\\|\/](.+)\..*$/$1/;
my $__log;


my $fields = {
	logname		=> undef,
	dir		=> undef,
	ext		=> undef,
	handle		=> undef
	};

sub new {
	croak "Only one log file instance allowed" if $__log;

	my $that = shift;
	my $class = ref($that) || $that;
	my $self = { %$fields };
	bless $self, $class;

	&__init($self);
	$__log = $self;

	return $self;
	}

sub setname ($) {
	$__name = shift;
	}

sub name {
	return $__name;
	}

sub timestamp {
	my ($sec, $min, $hour, $mday, $mon, $year, $rest)
		= localtime(time);

	return sprintf "[%02d-%3s-%04d %2d:%02d:%02d] ", 
			$mday,
			$__mnames[$mon],
			$year+1900,
			$hour,
			$min,
			$sec;
	}

sub print ($$) {
	my $self = shift;
	my $msg = shift;

	return unless $msg;

	my $fh = $self->{handle};

	print $fh &timestamp;
	print $fh $msg."\n";
	}

sub __init {
	my $self = shift;

	$self->{dir} = $__logdir;
	$self->{ext} = $__logext;
	$self->{logname} = $__logdir."/".$__name.".".$__logext;

	open $self->{handle}, ">> ".$self->{logname}
		or croak "Cannot open LOG => ".$self->{logname}."\n";


        autoflush STDERR 1;

	*STDERR = $self->{handle};

        autoflush STDERR 1;

	}

sub __fini {
	my $self = shift;
	close $self->{handle}
		or croak "Could not close LOG => ".$self->{logname}."\n";
	}

END	{ $__log->__fini() if $__log; }

1;
# }}}

# ---------------------------------------------------------------------
__END__
# Documentation {{{

=head1 NAME

	InCharge::Logger

=head1 SUMMARY

	Create and update log files

=head1 COPYRIGHT

 Copyright 1996-2005 by EMC Corporation ("EMC").
 All rights reserved.
 
 UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
 copyright notice above does not evidence any actual or intended
 publication of this software.  Disclosure and dissemination are
 pursuant to separate agreements. Unauthorized use, distribution or
 dissemination are strictly prohibited.

=head1 SYNOPSIS
	
	use InCharge::Logger;
	InCharge::Logger->setname("different");

	my $log = InCharge::Logger->new;

	$log->print("Hello, world\n");	# prints with timestamp
	print STDERR $log->timestamp()." Hello, world\n"; # same thing

=head1 DESCRIPTION

	A simple logging mechanism.

=head2 Data

=item B<logname>

	Full pathname of the open log file.

=item B<dir>

	Directory part of the B<logname>.
	This is fixed to "$SM_WRITEABLE/logs/".

=item B<ext>

	File extension part of the B<logname>,
	This is fixed to ".log".

=head2 Methods

=item B<new>

	Opens a log file in "$SM_WRITEABLE/logs/" with file extension
	".log".  The default name of the log is the basename of the
	"main::" calling script, without a file extension.

	E.g. if B<use>'d by a script name "my-perl-probe.pl",
	the log will be "$SM_WRITEABLE/logs/my-perl-probe.log"
	by default.

=item B<setname>(name)
	
	This allows a different name to be used for the log file.
	It is only effective I<before> the B<new> call
	(you guessed it -- that's why there's a I<new>!).

=item B<name>()

	Returns the log file's basename.

=item B<timestamp>()

	This returns a printable timestamp in a standard format.
	Internally called by B<print>.
	There if you want to use it for something else, but note
	that it's a function, not the time of last message logged.

=item B<print>(message)

	Appends the message with a timestamp prefix and ending
	newline to the log file. (Like I<print> in ASL.)

=head1 CAVEAT EMPTOR

	There is no way to change the log files directory from
	"$SM_WRITEABLE/logs/".
	Likewise,
	there is no way to change the log file extension from
	".log".

	There is also no way to I<not> print the timestamp with
	B<print>.
	If you want a multi-line log entry without replicated
	timestamps, use "print $log->{handle} $line" for the
	succeeding lines, or good old string concatenation across
	multiple lines, e.g.
		$log->print("First line\n"	# this gets stamped
			."Second line\n"	# no more free stamps!
			."Third line\n");

=head1 MODULE DEPENDENCIES

	Exporter
	Carp

=head1 AUTHOR

	(patterw@smarts.com)
	(guruprv@smarts.com)

=cut

# }}}
# vi:set ts=8 sw=8:
