#######################################################################
#
# SMARTS Logging Module 
# 
# Copyright 2007 by EMC Corporation ("EMC"). All Rights Reserved.
#
#######################################################################

package SMARTS::Logger;

use strict;
use warnings;
use 5.006_001;
use Carp qw(croak);
use Fcntl qw(:flock); 

our $VERSION = '1.2';

use Exporter;
use vars qw(@ISA @EXPORT);
@ISA = ('Exporter');
@EXPORT = qw(Logger);

#######################################################################
# The following is a persistent scope closure. It returns a reference
# to an anonymous subroutine. The scalar value is then dereferenced 
# using either the infix dereference operator (i.e. arrow operator)
# or using the more traditional prefix dereference operator (i.e. &$).
#######################################################################
sub Logger ($;$)
{
	my $file = shift;
	my $path = shift || ".";
	my $combined = "$path/$file";

	# override name if directory 
	if ($combined =~ /\/$/) {
                $main::0 =~ /.+[\\|\/](.+)$/;
                $combined = "$file".$1.".log";
	}

	return sub { 

			my $message = shift;

			eval {
				$|=1; # no buffering
				open(LOG, ">> $combined");
				flock(LOG, LOCK_EX); 
				print LOG "[".localtime()."] "."$message\n";
				flock(LOG, LOCK_UN);
				close(LOG);
			     };

			if ($@) { croak $@; }

		   };
}

1;

=head1 NAME

   SMARTS::Logger

=head1 SUMMARY

   Create and append to log files using a simple interface.

=head1 COPYRIGHT

   Copyright 2007 by EMC Corporation ("EMC"). All Rights Reserved.

=head1 SYNOPSIS

   use SMARTS::Logger;

   my $log = Logger("my_file.log");
   $log->("This is my message to log.");
   # message logged in './my_file.log'

   my $log2 = Logger("my_file.log", "my_directory");
   $log2->("This is my message to log.");
   # message logged in 'my_directory/my_file.log'

   my $log3 = Logger("../my_directory/my_file.log");
   $log3->("This is my message to log.");
   &$log3("This is another message to log!");
   # messages logged in '../my_directory/my_file.log'

   my $log4 = Logger("../my_directory/");
   $log4->("This is my message to log.");
   # message logged in '../my_directory/<script_name>.log'

   my $log5 = Logger("$ENV{SM_WRITEABLE}/logs/");
   $log5->("This is my message to log.");
   # message logged in '../smarts/local/logs/<script_name>.log'


=head1 DESCRIPTION

   A very simple logging mechanism.

=head1 MODULE DEPENDENCIES

   Exporter
   Carp
   Fcntl qw(:flock);	# used for cross-platform file locking

=head1 AUTHOR

   (pattew@emc.com)

=cut
