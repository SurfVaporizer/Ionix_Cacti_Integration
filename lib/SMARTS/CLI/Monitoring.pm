#######################################################################
#
# SMARTS Command Line Interface (CLI) Monitoring 
# 
# Copyright 2008 by EMC Corporation ("EMC"). All Rights Reserved.
#
# RCS $Id: Monitoring.pm,v 1.5 2007/08/15 15:35:31 gurupv Exp $
#
#######################################################################

package SMARTS::CLI::Monitoring;

use strict;
use warnings;
use 5.006_001;
use Carp qw(croak);

our $VERSION = '2.0';

use Exporter;

use vars qw(
		@ISA
		@EXPORT
		$MONITOR
		@DEBUG
		$LOG
		$SHELL
		$SYSTEM_NAME
		$ERROR
		$SM_OBJECT
		$SM_ATTRIBUTE
		$SM_PARAMETERS
           );

@ISA = ('Exporter');

@EXPORT = qw(
		$MONITOR
		@DEBUG
		$LOG
		$SHELL
		$SYSTEM_NAME
		$ERROR
		$SM_OBJECT
		$SM_ATTRIBUTE
		$SM_PARAMETERS
	    );

use InCharge::Monitoring;
use SMARTS::CLI::Remote;
use SMARTS::CLI::Remote::CommandLineDevice;
use SMARTS::Logger;

$MONITOR = InCharge::Monitoring->new;

my $serverName     = $$SM_PARAMETER{"ICServerName"};
my $accessId       = $$SM_PARAMETER{"AccessId"};
my $accessCode     = $$SM_PARAMETER{"AccessCode"};
my $deviceName     = $$SM_PARAMETER{"DeviceName"};
my $deviceIP       = $$SM_PARAMETER{"DeviceIP"};
my $timeout        = $$SM_PARAMETER{"Timeout"};
my $accessProtocol = $$SM_PARAMETER{"AccessProtocol"};
my $debugEnabled   = $$SM_PARAMETER{"DebugCode"};
my $prompt         = $$SM_PARAMETER{"Prompt"};
my $cliEnPass      = $$SM_PARAMETER{"EnableCode"};
my $conf	   = $$SM_PARAMETER{"config"};

my $max_buffer	   = 10*1048576;
my $ssh_client	   = "ssh";
my $ssh_args	   = "";
my $read_timeout   = 10;
my $enable_prompt  = '/[\w().-]*[\$#>]\s?(?:\(enable|reject|invalid|error|denied\))?\s*$/i';
my $login_prompt   = '/[\w().-]*[\$#>]\s?(?:\(enable\))?\s*$/';

$SYSTEM_NAME 	   = $deviceName;

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
			'prompt' => $prompt
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
           $ERROR = "Encountered a problem trying to login to '$deviceIP'. Got an error: $@\n Perhaps the AccessId '$accessId' or the AccessCode is incorrect!\n";
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
            push(@DEBUG, "Cannot log into enable mode for '$deviceIP'. Got an error: $@\nThe enable password might be wrong.\n");
    }

};

###################################################################
# If we have exceptions, throw them or exit clean.
###################################################################
if ($@) { croak $@; }

###################################################################
# If debugging is enabled, dump messages to the log file.
###################################################################
END { 
	if ($debugEnabled) { $LOG->("\n@DEBUG" . ('-' x 70)); } 
	if ($ERROR) { croak $ERROR; } else { exit 0; }
}

1;

=head1 NAME

   SMARTS::CLI::Monitoring;

=head1 SUMMARY

   A very simple interface for Monitoring Actions in Perl.

=head1 COPYRIGHT

   Copyright 2007 by EMC Corporation ("EMC"). All Rights Reserved.

=head1 SYNOPSIS

   use SMARTS::CLI::Monitoring;
  
   my @results = (); 
   eval { @results = $SHELL->cmd("who"); };
   if ($@) { push(@DEBUG, "Error: $@!\n"); }
   foreach (@results) { $LOG->("$_"); }

=head1 DESCRIPTION

   A simple interface for writing monitoring actions in Perl:

   [$MONITOR]

   This object handle is an InCharge::Monitoring.

   [$SHELL]

   This object handle is a SMARTS::CLI::Remote.

   [$LOG]

   This closure handle is a SMARTS::Logger.

   [@DEBUG]

   The contents of this array are dumped to the log file.

   [$SM_PARAMETERS]

   This is a reference to a hash containing the parameters:

   my $value = $$SM_PARAMETERS{'key'};
   my $value = $SM_PARAMETERS->{'key'};

   [$SM_ATTRIBUTE]

   This is a reference to a hash containing the return attributes:

   my $attribute = $$SM_ATTRIBUTE{'CLASS::INSTANCE::ATTRIBUTE'};
   $attribute->setvalue('return value for instrumented attribute');

   [$SM_OBJECT]

   A handle to the object which owns the instrumented attributes we update.

=head1 MODULE DEPENDENCIES

   Exporter
   Carp

   InCharge::Monitoring;
   SMARTS::CLI::Remote;
   SMARTS::Logger;

=head1 AUTHOR

   (pattew@emc.com)

=cut
