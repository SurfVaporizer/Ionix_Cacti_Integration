# ---------------------------------------------------------------------
#
# HostCmds.pm
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
# RCS $Id: HostCmds.pm,v 1.1 2008/10/09 17:05:33 mirkhr Exp $
# ---------------------------------------------------------------------

package serverhealth::HostCmds;

use strict;

use serverhealth::logging;
use Carp qw(croak carp);

# Solaris commands

# Discovery/Monitoring commands for CPU
my $cpu_cmdlist_sol  = {
                        discovery => 
                         [ 
                           "psrinfo" 
                         ],
                        monitoring =>
                         [ 
                           "kstat -p cpu_stat:CPUID::idle", 
                           "kstat -p cpu_stat:CPUID::user", 
                           "kstat -p cpu_stat:CPUID::kernel", 
                           "kstat -p cpu_stat:CPUID::swap", 
                           "kstat -p cpu_stat:CPUID::wait_io", 
                           "kstat -p cpu_stat:CPUID::wait_pio"
                         ]
                       };

# Discovery/Monitoring commands for process
my $proc_cmdlist_sol = {
                        discovery => 
                         [ 
                           "" 
                         ],
                        monitoring =>
                         [
                           "ps -o comm,args,vsz,s,rss,time -p "
                         ]
                       };

# Discovery/Monitoring commands for physical memory
my $pmem_cmdlist_sol = {
                        discovery => 
                         [ 
                           "" 
                         ],
                        monitoring =>
                         [
                           "prtconf", 
                           "kstat -p unix::system_pages:freemem", 
                         ]
                       };

# Discovery/Monitoring commands for virtual memory
my $vmem_cmdlist_sol = {
                        discovery => 
                         [ 
                           "" 
                         ],
                        monitoring =>
                         [
                           "swap -s"
                         ]
                       };

# linux commands

# Discovery/Monitoring commands for CPU
my $cpu_cmdlist_lin  = {
                        discovery => 
                         [ 
                           "cat /proc/cpuinfo " 
                         ],
                        monitoring =>
                         [ 
                           "cat /proc/stat " 
                         ]
                       };

# Discovery/Monitoring commands for process
my $proc_cmdlist_lin = {
                        discovery => 
                         [ 
                           "" 
                         ],
                        monitoring =>
                         [
                           "ps -o comm,s,time,vsz,rss,args --noheader -w -p "
                         ]
                       };

# Discovery/Monitoring commands for physical memory
my $pmem_cmdlist_lin = {
                        discovery => 
                         [ 
                           "" 
                         ],
                        monitoring =>
                         [
                           "cat /proc/meminfo " 
                         ]
                       };

# Discovery/Monitoring commands for virtual memory
my $vmem_cmdlist_lin = {
                        discovery => 
                         [ 
                           "" 
                         ],
                        monitoring =>
                         [
                           "cat /proc/meminfo " 
                         ]
                       };

my $Log;
my $header = "HostCmds.pm";

my $fields = {
              cpuCmds  => undef, 
              procCmds => undef, 
              pmemCmds => undef, 
              vmemCmds => undef 
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
     $self->{cpuCmds}  = $cpu_cmdlist_sol;
     $self->{procCmds} = $proc_cmdlist_sol;
     $self->{pmemCmds}  = $pmem_cmdlist_sol;
     $self->{vmemCmds}  = $vmem_cmdlist_sol;

  } elsif ($osName =~ /linux/) {
     $self->{cpuCmds}  = $cpu_cmdlist_lin;
     $self->{procCmds} = $proc_cmdlist_lin;
     $self->{pmemCmds}  = $pmem_cmdlist_lin;
     $self->{vmemCmds}  = $vmem_cmdlist_lin;

  } else {
     # nop
     ;
  }
}

sub getCpuCommands
{
   my $self = shift;
   my $type = shift; # discovery or monitoring commands

   if ($type =~ /discovery/) {
      return (%{ ($self->{cpuCmds}) })->{discovery};
   } 
   elsif ($type =~ /monitoring/) {
      return (%{ ($self->{cpuCmds}) })->{monitoring};
   }
}

sub getProcessCommands
{
   my $self = shift;
   my $type = shift; # discovery or monitoring commands

   if ($type =~ /discovery/) {
      return (%{ ($self->{procCmds}) })->{discovery};
   } 
   elsif ($type =~ /monitoring/) {
      return (%{ ($self->{procCmds}) })->{monitoring};
   }
}

sub getPMemCommands
{
   my $self = shift;
   my $type = shift; # discovery or monitoring commands

   if ($type =~ /discovery/) {
      return (%{ ($self->{pmemCmds}) })->{discovery};
   } 
   elsif ($type =~ /monitoring/) {
      return (%{ ($self->{pmemCmds}) })->{monitoring};
   }
}

sub getVMemCommands
{
   my $self = shift;
   my $type = shift; # discovery or monitoring commands

   if ($type =~ /discovery/) {
      return (%{ ($self->{vmemCmds}) })->{discovery};
   } 
   elsif ($type =~ /monitoring/) {
      return (%{ ($self->{vmemCmds}) })->{monitoring};
   }
}

END
{
  if ( defined( $Log )) {
    $Log->printdebug("End of $header");
  }
}
