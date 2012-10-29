# ---------------------------------------------------------------------
#
# CmdExec.pm 
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
# RCS $Id: CmdExec.pm,v 1.1.2.2 2009/09/14 23:57:27 mirkhr Exp $
# ---------------------------------------------------------------------


package serverhealth::CmdExec;

use strict;

use serverhealth::logging;

my $fields = {
               cmdList => ()
             };
my ($Log);
my $header = "CmdExec.pm";

sub new
{
   my $that = shift;
   my $class = ref($that) || $that;
   my $self = { %$fields };

   bless $self, $class;

   $Log = serverhealth::logging->get($header);

   # Fill the command list
   &init($self, @_);

   # Run the commands
   my $cmdOp = &run( $self );

   # clear the local hash for the commands
   &clearCmdList( $self );

   return $cmdOp;
}

sub init
{
  my ($self, $cmdList) = @_;
  
  $self->{cmdList} = $cmdList;
  $Log->printdebug("Commands filed in CmdList are: @{ $self->{cmdList} }");
}

sub run
{
   my $self = shift;
   my $cmd, my @cmdOutput = ();
   my $index;

   $Log->printdebug("Commands in CmdExec run are: @{ $self->{cmdList} }");

   foreach $cmd (@{ $self->{cmdList} }) {
 
      # Get the outputfile name to populate its header and then footer
      my $outputfile = get_outputfilename( $cmd );
      $Log->printdebug("Outputfile is: $outputfile");
      # Populate the header
      if ( $outputfile ne "" ) {
        my $lt = localtime();
        `echo "Command: " >> $outputfile`;
        `echo " "`;
        `echo "$cmd " >> $outputfile`;
        `echo " "`;
        `echo "executed at: $lt " >> $outputfile`;
        `echo " "`;
        `echo "============================================================" >> $outputfile`;
      }

      # Execute the actual command
      $Log->printdebug("Executing the command: $cmd");
      $cmdOutput[$index++] = `$cmd`;
      $Log->printdebug("Output of the cmd: $cmd is $cmdOutput[$index-1]");
  
      # Populate the footer
      if ( $outputfile ne "" ) {
        `echo "============================================================" >> $outputfile`;
      }
   }
   return [ @cmdOutput ];
}

# This subroutine returns the name of the outputfile specified in the cmd
# sent as the one and the only argument.
# The command can be anyone of the following:
# ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE
# DMCTL -s SRVNAME exec dmdebug --queues --append --output=OUTPUT_FILE
# In both the above cases, the returned filename is OUTPUT_FILE

sub get_outputfilename
{
   my $cmd = shift;

   my $filename = "";
   my $pattern1 = ">";
   my $pattern2 = "--output=";

   my $index = index( $cmd, $pattern1 );
   if ( $index != -1 ) {
     # of the type ">" or ">>"
     my $index2 = index( $cmd, $pattern1, $index+1 );
     if ( $index2 != -1 ) {
       # of the type ">>"
       $filename = substr( $cmd, ($index2+1 )); 
     }
     else {
       # of the type ">"
       $filename = substr( $cmd, ($index+1) ); 
     }
   }
   else {
      # of the type "--output="
      my $index2 = index( $cmd, $pattern2 );
      if ( $index2 != -1 ) {
         $filename = substr( $cmd, $index2 + length( $pattern2 )); 
      }
   }
   if ( $filename ne "" ) {
     if ( $cmd =~ /dmctl/ && $cmd =~ /--output/ ) {
       $filename = $ENV{SM_WRITEABLE}."/logs/" . $filename;
     }
     return( $filename );
   }
   else {
     return( "" );
   }
}

sub clearCmdList
{
  my $self = shift;
  $self->{CmdList} = undef;
}

END {
   #$Log->printdebug("END of CmdExec");
   #$Log->close;
}
