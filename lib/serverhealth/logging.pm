# ---------------------------------------------------------------------
#
# logging.pm 
#
# Copyright 1996-2008 by EMC Corporation ("EMC").
# All rights reserved.
#
# UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
# copyright notice above does not evidence any actual or intended
# publication of this software.  Disclosure and dissemination are
# pursuant to separate agreements. Unauthorized use, distribution or
# dissemination are strictly prohibited.
#
# RCS $Id: logging.pm,v 1.1 2008/10/09 17:05:33 mirkhr Exp $
# ---------------------------------------------------------------------


package serverhealth::logging;

use strict;

use Carp qw(croak carp);
use InCharge::session;

my $isLogFileEnabled = 1;
my $logFileNamePrefix = "host-perl-";
my $logFileDir = $ENV{SM_WRITEABLE}."/logs/";
my $icServerName; 
my $__log;

my $fields = {
               debug => 0,
               logFileName => "",
               packageName => "",
               type => "",
               fildes => undef
               };

#  Examples of Usage:
#  my $Log = logging->new();
#  my $Log = logging->new(__PACKAGE__, debug, logfileName, type);
#  my $Log = logging->new(__PACKAGE__);

sub new
{
   my $that = shift;
   my $class = ref($that) || $that;
   my $self = { %$fields };

   bless $self, $class;

   # Extract the DM Name
   if ($main::ARGV[0] =~ /^--server=([-\w.]+)\:(\d+)\/([-\w]+)/) {
       # discovery log
       $icServerName = $3;
   } else {
       # Monitoring log, servername and log name filled in externally
       $icServerName = "";
   }

   &init($self, @_);

   $__log = $self; 

   return $self;
}

sub get
{
   # If the log file is already open, return the existing one, after 
   # modifying the header(__PACKAGE__) that appears in the log file

   if ($__log) {
      if (defined ($_[1])) {
         $__log->{packageName} = $_[1];
      }
      return ($__log);
   }
   # Log file was not created yet
   return &new;
}

sub init
{
  my ($self, $lPackageName, $lDebug, $logName, $type) = @_;
  
  # Enable or disable logging
  if ( defined($lDebug) ) {
     # enabled/disable logging according to the input param
     $self->{debug} = $lDebug;
  } 

  # Package name supplied externally or internally - appears as header in log
  if ( defined($lPackageName) ) {
    $self->{packageName} = $lPackageName;
  }
  else {
    $self->{packageName} = __PACKAGE__;
  }

  # log type - whether for discovery (default) or for monitoring
  if ( defined($type) ) {
    $self->{type} = $type;
  } else {
    $self->{type} = "discovery";
  }

  # Log name supplied externally or to be built internally
  if ( defined($logName) ) {
    $self->{logFileName} = $logFileDir.$logName;
  }
  else {
    $self->{logFileName} = $logFileDir.
                           $logFileNamePrefix.
                           $self->{type}.
                           "-".
                           $icServerName.
                           ".log"; 
  }

  $isLogFileEnabled = 1;

  # open the log file
  unless( open($self->{fildes}, ">> ".$self->{logFileName}) ) {
          print "Error: cannot access $self->{logFileName}.Logging disabled.\n";
          $isLogFileEnabled = 0;
  }
  printdebug($self, "Opening the logging file in logging.pm");
  
}

sub close
{
   my $self = shift;
   local (*FILEHANDLE) = $self->{fildes};
   if (defined( $self->{fildes} )) {
     printdebug($self, "-" x 20);
     close FILEHANDLE;
   }
}

# appends strings to filehandle DBG with debug log header
# input: log string
sub printdebug() {
   my ($self, $logMsg) = @_;
   my $logHeader = "[".(scalar localtime)."] ";

   if ($self->{debug}) {
      #println("$self->{packageName}: $logHeader $logMsg");
      println($self->{fildes}, "$self->{packageName}: $logHeader $logMsg");
   }
}

# appends strings to filehandle DBG with log header
# input: log string
sub printlog() {
   my ($self, $logMsg) = @_;
   my $logHeader = "[".(scalar localtime)."] ";

   #println("$self->{packageName}: $logHeader $logMsg");
   println($self->{fildes}, "$self->{packageName}: $logHeader $logMsg");
}

sub println() {
   local (*FILEHANDLE) = shift;
   my $logMsg = shift;
   if ($isLogFileEnabled) {
      print FILEHANDLE "$logMsg\n";
   }
}

END {
   #if ( defined($__log) ) {
   #  println($__log, "-" x 80);
   #  close $__log->{fildes};
   #}
}
