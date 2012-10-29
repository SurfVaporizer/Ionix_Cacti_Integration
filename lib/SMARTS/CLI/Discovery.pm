#######################################################################
#
# SMARTS Command Line Interface (CLI) Discovery 
# 
# Copyright 2008 by EMC Corporation ("EMC"). All Rights Reserved.
#
# RCS $Id: Discovery.pm,v 1.5 2007/08/15 15:35:31 gurupv Exp $
#
#######################################################################

package SMARTS::CLI::Discovery;

use strict;
use warnings;
use 5.006_001;
use Carp qw(croak);

our $VERSION = '2.0';

use Exporter;

use vars qw(
		@ISA
		@EXPORT
		@DEBUG
		$LOG
		$SHELL
		$SESSION
		$GA_PARAMS
		$PROBE
		$SYSTEM
		$SYSTEM_NAME
		$ERROR
           );

@ISA = ('Exporter');

@EXPORT = qw(
		@DEBUG
		$LOG
		$SHELL
		$SESSION
		$GA_PARAMS
		$PROBE
		$SYSTEM
		$SYSTEM_NAME
		$ERROR
	    );

use InCharge::Probe;
use SMARTS::CLI::Remote;
use SMARTS::CLI::Remote::CommandLineDevice;
use SMARTS::Logger;

###################################################################
# Fetching Input Parameters and Establishing Default Object Handles
###################################################################

# fetch a session handle to the domain that launched us
$PROBE                  = InCharge::Probe->new;
$SESSION                = $PROBE->{session};
$GA_PARAMS              = $PROBE->{ga_params};

my $serverName		= $SESSION->getServerName();
my $elementName         = $$GA_PARAMS{"elementName"};
my $elementType         = $$GA_PARAMS{"elementType"};
my $accessCode          = $$GA_PARAMS{"AccessCode"};
my $accessId            = $$GA_PARAMS{"AccessId"};
my $accessProtocol      = $$GA_PARAMS{"AccessProtocol"};
my $timeout             = $$GA_PARAMS{"Timeout"};
my $debugEnabled        = $$GA_PARAMS{"DebugEnabled"};
my $prompt              = $$GA_PARAMS{"Prompt"};
my $cliEnPass           = $$GA_PARAMS{"EnableCode"};
my $agentObj		= $SESSION->object("SNMPAgent", $elementName);
my $systemName          = $agentObj->getSystem();
my $sysObj              = $SESSION->object($systemName);
my $sysName             = $sysObj->{"Name"};

# XXX - This depends on things which are in the application models and not
#       the reference ones so for testing fallback to the name
my $deviceIP            = $agentObj->{"AgentAddress"};

if ($deviceIP eq "") {
	$deviceIP = $elementName;
}

my $manager		= $SESSION->object("ICF_PersistenceManager", "ICF-PersistenceManager");
my $conf		= $manager->{"config"};

my $max_buffer		= 10*1048576;
my $ssh_client		= "ssh";
my $ssh_args		= "";
my $read_timeout	= 10;
my $enable_prompt	= '/[\w().-]*[\$#>]\s?(?:\(enable|reject|invalid|error|denied\))?\s*$/i';

$SYSTEM 		= $sysObj;
$SYSTEM_NAME		= $sysName;

###################################################################
# Utility routines
###################################################################
sub get_log_dir {

	if ( $ENV{SM_LOGFILES} ) {
		if( $ENV{SM_LOGFILES} =~ m/([.]{2})/i ) {
			croak "Failure: ENV{SM_LOGFILES} does not contain \"../\" path.\n";
		}
	
		if ( -d $ENV{SM_LOGFILES} ) {
			if ( -w $ENV{SM_LOGFILES} ) {
				return $ENV{SM_LOGFILES};
			}
		}
	}

	if ( $ENV{SM_WRITEABLE} ) {
		if( $ENV{SM_WRITEABLE} =~ m/([.]{2})/i ) {
       			croak "Failure: ENV{SM_WRITEABLE} does not contain \"../\" path.\n";
		}

		if ( -d $ENV{SM_WRITEABLE} ) {
                        if ( -w $ENV{SM_WRITEABLE} ) {
                                return $ENV{SM_WRITEABLE}."/logs";
            		}
             	}
	 } else {
                croak "Failure: unable to find a directory to write logs.\n";
	 }
}

sub get_conf_file {
    my $conf_file = shift;
	my @conf_dirs = split /:|;/, $ENV{SM_SITEMOD};
	for my $conf_dir (@conf_dirs) {
		my $file = $conf_dir."/conf/$conf/".$conf_file;
		if ( -f $file ) {
                        return $file;
		}
	}
        return "";
}

sub read_config
{
 	my $file = shift;
	my %table = ();

	open(FILE, "< $file") || croak "Failure: unable to open '$file'!\n";

	while (<FILE>) {
		chomp;
       		s/#.*//;
		s/^\s+//;
		s/\s+$//;
		next unless length;
		my ($key, $value) = split(/\s*=\s*/, $_, 2);
		$table{$key} = $value;
	}

	close(FILE) || croak "Failure: unable to close '$file'!\n";

	return %table;
}

###################################################################
# Override
###################################################################
my %config = ();
my $conf_file = "perl-cli.conf";

my $file = get_conf_file("$conf_file");
if ( $file eq "" ) {
	croak "Failure: unable to find cli conf file!\n";
} else {
        %config = &read_config("$file");
}

if (keys(%config)) {
  if ($config{debug}        ){ $debugEnabled  = $config{debug};     }
  if ($config{ssh_client}   ){ $ssh_client    = $config{ssh_client};}
  if ($config{ssh_args}     ){ $ssh_args      = $config{ssh_args};  }
  if ($config{max_buffer}   ){ $max_buffer    = $config{max_buffer};}
  if ($config{timeout}      ){ $timeout       = $config{timeout};   }
  if ($config{read_timeout} ){ $read_timeout  = $config{read_timeout};  }
  if ($config{prompt}       ){ $prompt        = $config{prompt};    }
  if ($config{enable_prompt}){ $enable_prompt = $config{enable_prompt}; }
}

###################################################################
# Debugging Support
###################################################################
if ($debugEnabled) {
	$LOG = sub {}; 
	my $logDir = get_log_dir();
	my $logFile = $0;
	$logFile =~ s/.+[\\|\/](.+)$/$1/; 
	$logFile = $logFile.".$serverName.log"; 
	$LOG = Logger($logFile, $logDir);  
}

eval {
    if ($accessProtocol eq "TELNET") {
       eval {
            $SHELL = SMARTS::CLI::Remote->new(
            	"Net::Telnet",
                $deviceIP,
		undef,
		undef,
		(
			'timeout' => $timeout,
			'prompt' => $prompt,
		)
   	    );
        };
        if ($@) {
	   $ERROR = "$accessProtocol encountered a problem!\n$@\n";
           push(@DEBUG, "Device: $deviceIP");
           push(@DEBUG, "$ERROR\n");
           exit 0;
        }
        goto LOGIN;
    }

    if ($accessProtocol eq "SSH1") {
        eval {
            $SHELL = SMARTS::CLI::Remote->new(
            	"ext",
                $deviceIP,
		undef,
		undef,
		( 
			'timeout'  => $timeout, 
			'protocol' => 1,
			'ext_cmd'  => $ssh_client,
			'ext_args' => $ssh_args,
			'prompt'   => $prompt,
		)

	    );
        };
        if ($@) {
	   $ERROR = "$accessProtocol encountered a problem!\n$@\n";
           push(@DEBUG, "Device: $deviceIP");
           push(@DEBUG, "$ERROR\n");
           exit 0;
        }
        goto LOGIN;
    }

    if ($accessProtocol eq "SSH2") {
        eval {
            $SHELL = SMARTS::CLI::Remote->new(
            	"ext",
                $deviceIP,
		undef,
		undef,
		( 
			'timeout'  => $timeout, 
			'protocol' => 2,
			'ext_cmd'  => $ssh_client,
			'ext_args' => $ssh_args,
	                'prompt'   => $prompt,
		)

	    );
        };
        if ($@) {
	   $ERROR = "$accessProtocol encountered a problem!\n$@\n";
           push(@DEBUG, "Device: $deviceIP");
           push(@DEBUG, "$ERROR\n");
           exit 0;
        }
        goto LOGIN;
    }
    
    if ($accessProtocol eq "netSSH1") {
        eval {
            $SHELL = SMARTS::CLI::Remote->new(
            	"Net::SSH::Perl",
                $deviceIP,
		undef,
		undef,
		( 
			'_debug' => 1,
			'timeout'  => $timeout, 
			'protocol' => 1,
			'ext_cmd'  => $ssh_client,
			'ext_args' => $ssh_args,
	                'prompt'   => $prompt,
		)

	    );
        };
        if ($@) {
	   $ERROR = "$accessProtocol encountered a problem!\n$@\n";
           push(@DEBUG, "Device: $deviceIP");
           push(@DEBUG, "$ERROR\n");
           exit 0;
        }
        goto LOGIN;
    }
    
    if ($accessProtocol eq "netSSH2") {
        eval {
            $SHELL = SMARTS::CLI::Remote->new(
            	"Net::SSH::Perl",
                $deviceIP,
		undef,
		undef,
		( 
			'timeout'  => $timeout, 
			'protocol' => 2,
			'ext_cmd'  => $ssh_client,
			'ext_args' => $ssh_args,
	                'prompt'   => $prompt,
		)

	    );
        };
        if ($@) {
	   $ERROR = "$accessProtocol encountered a problem!\n$@\n";
           push(@DEBUG, "Device: $deviceIP");
           push(@DEBUG, "$ERROR\n");
           exit 0;
        }
        goto LOGIN;
    }
    
    if ($accessProtocol) {
    	$ERROR = "The AccessProtocol $accessProtocol is unsupported for '$deviceIP'!\n";
    } else {
    	$ERROR = "Did not receive all necessary parameters for '$deviceIP' to be discovered!\n";
    }
    push(@DEBUG, $ERROR);
    exit 0;

    LOGIN:
    # login to remote device
    eval { $SHELL->max_buffer_length($max_buffer); };
    eval { $SHELL->login($accessId, $accessCode); };
    if ($@) {
           $ERROR = "Encountered a problem trying to login to '$deviceIP'. Got error: $@\n Perhaps the AccessId '$accessId' or the AccessCode is incorrect!\n";
           push(@DEBUG, "$ERROR\n");
	   exit 0;
    }

###################################################################
# Enable Mode Support
###################################################################

    my $output = "";
    eval {
        if ($cliEnPass ne "") {
            $SHELL->setReadTimeout($read_timeout);
            $SHELL->cmd("enable", '/password: $/i');
            $output = $SHELL->cmd($cliEnPass, $enable_prompt);
        }
    };

    if ($@ || ($output =~ /(reject|invalid|error|denied)/i)) {
            push(@DEBUG, "Cannot log into enable mode for '$deviceIP'. Got error: $@\nThe enable password might be wrong.\n");
    }

};

###################################################################
# If we have exceptions, throw them or exit clean.
###################################################################
if ($@) { $PROBE->stop($@); } 

###################################################################
# Stop the probe and detach the session. If debugging is enabled,
# dump messages to the log file.
###################################################################
END { 
	if ($debugEnabled) { $LOG->("\n@DEBUG" . ('-' x 70)); } 
	if ($ERROR) { 
		$PROBE->stop("$ERROR");
	} else { 
		$PROBE->setProbeResult("SUCCESS");
		$PROBE->setChanged("TRUE");
		$PROBE->setDiscoveryError("");
		$PROBE->setElementObjectName($elementName);
		$PROBE->stop(); 
	}
	$SESSION->detach();
}

1;

__END__

=pod 

=head1 NAME

B<SMARTS::CLI::Discovery>
A very simple interface for discovery probes in Perl.

=head1 COPYRIGHT

Copyright 2005-2007 by EMC Corporation ("EMC").
All rights reserved.

UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The copyright
notice above does not evidence any actual or intended publication of
this software.  Disclosure and dissemination are pursuant to separate
agreements.  Unauthorized use, distribution or dissemination are
strictly prohibited.

=head1 SYNOPSIS

   use SMARTS::CLI::Discovery;
  
   my @results = (); 

   eval { @results = $SHELL->cmd("who"); };
   if ($@) { push(@DEBUG, "Error: $@!\n"); }

   foreach (@results) { 
	# parse the command output
   }

   $ERROR = $@;

=head1 DESCRIPTION

A simple interface for writing discovery probes in Perl.

C<$PROBE>

This object handle is an C<InCharge::Probe>.

C<$SHELL>

This object handle is a C<SMARTS::CLI::Remote>.

C<$SESSION>

This object handle is a C<InCharge::session>.

C<$LOG>

This closure handle is a C<SMARTS::Logger>.

C<@DEBUG>

The contents of this array are dumped to the log file.

C<$GA_PARAMS>

Hash table containing the parameters. E.g.

	my $value = $$GA_PARAMS{'key'};

C<$SYSTEM>

A handle to the system object.

C<$ERROR>

If an exception is thrown, set C<$ERROR> and the probe status is returned.

=head1 MODULE DEPENDENCIES

C<Exporter>

C<Carp>

C<InCharge::Probe>

C<SMARTS::CLI::Remote>

C<SMARTS::Logger>

=head1 AUTHOR

I<pattew@emc.com>

=cut
