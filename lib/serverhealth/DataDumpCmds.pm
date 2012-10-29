# ---------------------------------------------------------------------
#
# DataDumpCmds.pm
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
# RCS $Id: DataDumpCmds.pm,v 1.1.2.9 2009/01/23 21:06:00 mirkhr Exp $
# ---------------------------------------------------------------------

package serverhealth::DataDumpCmds;

use strict;

use serverhealth::logging;
use Carp qw(croak carp);

# Solaris commands

# Commands used upon detection of Host related events
my $host_cmdlist_sol  = {
                        HighCpuUtilization => 
                         [ 
                           "top -d2 -s2 >> OUTPUT_FILE",
                           "prstat -a 2 2 >> OUTPUT_FILE" 
                         ],
                        HighPhysicalMemoryUtilization => 
                         [ 
                           "top -d2 -s2 >> OUTPUT_FILE" 
                         ],
                        HighVirtualMemoryUtilization => 
                         [ 
                           "top -d2 -s2 >> OUTPUT_FILE", 
                           "swap -s >> OUTPUT_FILE"
                         ]
                       };

# Commands used upon detection of InChargeService related events
my $icsrv_cmdlist_sol = {
                        FullDiscoveryTimeExceeded => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        PendingDiscoveryTimeExceeded => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        HighCPUProcessUtilization => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        ApproachingMemoryResourceLimit => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE" 
                         ],
                        HighPhysicalMemoryUtilization => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE" 
                         ],
                        ApproachingCpuResourceLimit => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE" 
                         ],
			ApproachingMaxFileHandlesLimit =>
			 [
			   "pstack PID >> OUTPUT_FILE",
			   "lsof -p PID >> OUTPUT_FILE",
			   "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
			 ],
                        RunningOutOfMemory =>
                        [
                          "pmap -x PID >> OUTPUT_FILE",
                          "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface getQueueList_r >> OUTPUT_FILE",
                          "DMCTL -s SRVNAME exec dmdebug --clients --append --output=OUTPUT_FILE"
                        ]
                       };

# Commands used upon detection of Queue related events
my $queue_cmdlist_sol = {
                        QueueNotServiced => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface getQueueList_r >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME exec dmdebug --clients --append --output=OUTPUT_FILE",
                         ],
                        QueueBacklogged => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "prstat -mL -p PID 1 1 >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface getQueueList_r >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME exec dmdebug --clients --append --output=OUTPUT_FILE",
                         ]
                       };
# linux commands

# Commands used upon detection of Queue related events
my $queue_cmdlist_lin = {
                        QueueNotServiced => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE",
                           "SM_PERL SCRIPT_PATH/linux_prstat.pl >> OUTPUT_FILE",
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface getQueueList_r >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME exec dmdebug --clients --append --output=OUTPUT_FILE",
                         ],
                        QueueBacklogged => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE",
                           "SM_PERL SCRIPT_PATH/linux_prstat.pl >> OUTPUT_FILE",
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface getQueueList_r >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME exec dmdebug --clients --append --output=OUTPUT_FILE",
                         ]
                       };
# Commands used upon detection of Host related events
my $host_cmdlist_lin  = {
                        HighCpuUtilization => 
                         [ 
                           "top -b -d2 -n2 >> OUTPUT_FILE",
                           "SM_PERL SCRIPT_PATH/linux_prstat.pl >> OUTPUT_FILE" 
                         ],
                        HighPhysicalMemoryUtilization => 
                         [ 
                           "top -b -d2 -n2  >> OUTPUT_FILE"
                         ],
                        HighVirtualMemoryUtilization => 
                         [ 
                           "top -b -d2 -n2 >> OUTPUT_FILE"
                         ]
                       };

# Commands used upon detection of InChargeService related events
my $icsrv_cmdlist_lin = {
                        FullDiscoveryTimeExceeded => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        PendingDiscoveryTimeExceeded => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        HighCPUProcessUtilization => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        ApproachingMemoryResourceLimit => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE" 
                         ],
                        HighPhysicalMemoryUtilization => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE" 
                         ],
                        ApproachingCpuResourceLimit => 
                         [ 
                           "ps -ocomm,args,vsz,rss,time -p PID >> OUTPUT_FILE",
                           "ps -xm -p PID >> OUTPUT_FILE", 
                           "pstack PID >> OUTPUT_FILE" 
                         ],
			ApproachingMaxFileHandlesLimit =>
                         [
                           "pstack PID >> OUTPUT_FILE",
                           "lsof -p PID >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface dumpLocks|more"
                         ],
                        RunningOutOfMemory =>
                        [
                          "pmap -x PID >> OUTPUT_FILE",
                          "cat /proc/PID/maps >> OUTPUT_FILE",
                          "cat /proc/PID/status >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME invoke DM_MetricsInterface::DM-MetricsInterface getQueueList_r >> OUTPUT_FILE",
                           "DMCTL -s SRVNAME exec dmdebug --clients --append --output=OUTPUT_FILE",
                           "SM_PERL SCRIPT_PATH/linux_prstat.pl >> OUTPUT_FILE",
                        ]
                       };

my $Log;
my $header = "DataDumpCmds.pm";

my $fields = {
              hostCmds  => undef, 
              icsrvCmds => undef,
              queueCmds => undef
             };

sub new 
{
     my $that = shift;
     my $class = ref($that) || $that;
     my $self = { %$fields };

     bless $self, $class;

     $Log = serverhealth::logging->get( $header );

     # Fill the correct commands depending upon the platform
     &init( $self ); 
     
     return $self;
}

sub init 
{
  my ($self) = shift;
  my ($osName) = $^O;

  $Log->printdebug("Operating system is: $osName");
  if ($osName =~ /solaris/) {
     $self->{hostCmds}  = $host_cmdlist_sol;
     $self->{icsrvCmds} = $icsrv_cmdlist_sol;
     $self->{queueCmds} = $queue_cmdlist_sol;

  } elsif ($osName =~ /linux/) {
     $self->{hostCmds}  = $host_cmdlist_lin;
     $self->{icsrvCmds} = $icsrv_cmdlist_lin;
     $self->{queueCmds} = $queue_cmdlist_lin;

  } else {
     # nop
     ;
  }
}

sub getHostCommands
{
   my $self = shift;
   my $type = shift; # event name

   if ($type =~ /HighCpuUtilization/) {
      return (%{ ($self->{hostCmds}) })->{HighCpuUtilization};
   } 
   elsif ($type =~ /HighPhysicalMemoryUtilization/) {
      return (%{ ($self->{hostCmds}) })->{HighPhysicalMemoryUtilization};
   }
   elsif ($type =~ /HighVirtualMemoryUtilization/) {
      return (%{ ($self->{hostCmds}) })->{HighVirtualMemoryUtilization};
   }
}

sub getIcsrvCommands
{
   my $self = shift;
   my $type = shift; # event name

   if ($type =~ /HighCPUProcessUtilization/) {
      return (%{ ($self->{icsrvCmds}) })->{HighCPUProcessUtilization};
   } 
   elsif ($type =~ /FullDiscoveryTimeExceeded/) {
      return (%{ ($self->{icsrvCmds}) })->{FullDiscoveryTimeExceeded};
   } 
   elsif ($type =~ /PendingDiscoveryTimeExceeded/) {
      return (%{ ($self->{icsrvCmds}) })->{PendingDiscoveryTimeExceeded};
   } 
   elsif ($type =~ /ApproachingMemoryResourceLimit/) {
      return (%{ ($self->{icsrvCmds}) })->{ApproachingMemoryResourceLimit};
   } 
   elsif ($type =~ /HighPhysicalMemoryUtilization/) {
      return (%{ ($self->{icsrvCmds}) })->{HighPhysicalMemoryUtilization};
   } 
   elsif ($type =~ /ApproachingCpuResourceLimit/) {
      return (%{ ($self->{icsrvCmds}) })->{ApproachingCpuResourceLimit};
   } 
   elsif ($type =~ /ApproachingMaxFileHandlesLimit/) {
      return (%{ ($self->{icsrvCmds}) })->{ApproachingMaxFileHandlesLimit};
   } 
   elsif ($type =~ /RunningOutOfMemory/) {
      return (%{ ($self->{icsrvCmds}) })->{RunningOutOfMemory};
   }
}

sub getQueueCommands
{
   my $self = shift;
   my $type = shift; # event name

   if ($type =~ /QueueNotServiced/) {
      return (%{ ($self->{queueCmds}) })->{QueueNotServiced};
   } 
   elsif ($type =~ /QueueBacklogged/) {
      return (%{ ($self->{queueCmds}) })->{QueueBacklogged};
   } 
}

END
{
  if ( defined( $Log )) {
    $Log->printdebug("End of $header");
  }
}
