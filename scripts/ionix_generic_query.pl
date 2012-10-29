#!/usr/bin/perl
# -- Author: Skribnik Evgeniy
# -- This program is free software; you can redistribute it and/or
# -- modify it under the terms of the GNU General Public License
# -- as published by the Free Software Foundation;

# -- Description:

# -- ChangeLog
# -- Version: 0.1b

BEGIN {
	# -- insert cacti path to "cacti_path" variable
	our $cacti_path = "/var/www/html/cacti/";
	our $integration_path = $cacti_path."ionix_integration/";
	our $lib_path = $integration_path."lib/";
	our $lib_perl_path = $integration_path."lib/lib/perl5";
	
	our $conf_file = $integration_path."main.cfg";
}
# -- Import ionix Perl API library
use lib $lib_path;
use lib $lib_perl_path;

# -- required modules
use Config::Simple;
use InCharge::session;
use Data::Dumper;
use utf8;

# -- Import common procedures file
require "$integration_path/scripts/common_procs.pl";

# -- load global configuration file
%confHash = ();
%confHash =  load_config($conf_file);

# -- ionix credentials
my $sm_username = $confHash{'ionix.sm_username'};
my $sm_password = $confHash{'ionix.sm_password'};
my $samManager = $confHash{'ionix.samManager'};

# -- get list of sam managers from config
my $ref = $cfg->param(-block=>'instrumentation_keys');
my %instrumentation_keys = %$ref; 

my $hostname = $ARGV[0];
my $pattern_class_name = $ARGV[1];

my $debug = 0;

my %pattern_class_methods = ();
$pattern_class_methods{"Interface"}{get} =  "getInterfaces";
$pattern_class_methods{"Interface"}{find} =  "findNetworkAdapterByDeviceID";

$pattern_class_methods{"Port"}{get} =  "getPorts";
$pattern_class_methods{"Port"}{find} =  "findNetworkAdapterByDeviceID";

$pattern_class_methods{"NetworkAdapter"}{get} =  "getNetworkAdapters";
$pattern_class_methods{"NetworkAdapter"}{find} =  "findNetworkAdapterByDeviceID";

$pattern_class_methods{"TemperatureSensor"}{get} =  "getTemperatureSensors";
$pattern_class_methods{"TemperatureSensor"}{find} =  "findTemperatureSensor";

$pattern_class_methods{"Processor"}{get} =  "getProcessors";
$pattern_class_methods{"Processor"}{find} =  "findProcessor";


if ($hostname eq "" || $pattern_class_name eq "") {
	print "Error: too few arguments\n";
	help();
	exit;
}

# -- get apm name from device hostname (e.g: vt-apm:localhost)
my @arr = split('::', $hostname);

$broker = $arr[0];
$sam_manager = $arr[1];
$apm_manager = $arr[2];
$device_class = $arr[3];
my $hostname = $arr[4];

if ($apm_manager eq "" || $hostname eq "" || $broker eq "") {
	print "Error: unable to parse \"$hostname\" variable\n";
	exit;
}

# -- connect to APM to get data
my $session = eval { dmConnect($broker, $apm_manager, $sm_username, $sm_password); };
if ($@) {
	print "Error: $@\n";
	exit;
}

# -- get object of device
my $devObj = eval { $session->object($device_class, $hostname); };
if ($@) {
	print "Error: unable to get object of \"$device_class :: $hostname\"\n";
	exit;
}

# -- check if object not Null
if ($devObj->isNull()) {
	print "Error: device \"$hostname\" is null\n";
	exit;
}

my $i = 0;

# -- run pattern method on device object
my $get_method = $pattern_class_methods{$pattern_class_name}{get};
my $find_method = $pattern_class_methods{$pattern_class_name}{find};

# -- return result of get command (e.g: perl ionix_generic_query.pl "sam::apm::Router::example.domain.com" Interface get Type <DeviceID>)
if ($ARGV[2] eq "get") {
	my $device_id = $ARGV[4];
	my $attribute = $ARGV[3];
	my $result = "";
	
	my @arr = ($device_id);
	my $elem = eval { $session->invoke($devObj, $find_method, @arr); };
	if ($@) {
		print "Error: unable to find $device_id on $devObj->{DisplayName} \"$@\"\n";
	}
	else {
		if ($elem ne "") {
			# -- get object of found element
			my $inst_obj = eval { $session->object($elem); };
			if ($@) {
				print "Error: unable to get object of \"$elem\"\n";
			}
			else {
				$result = eval { $inst_obj->get($attribute); };
				if ($@) {
					if ($debug) { print "Debug: Attribute \"$attribute\" not exists in class $inst_obj->{CreationClassName}\n"; }
			
					# -- if current class has Instrumentation Key then check attribute in Istrumentation class
					my $class = $inst_obj->{CreationClassName};
					my $key = $instrumentation_keys{$class};
					if ($key) {
						$result = check_instrumentation($key, $inst_obj, $attribute);
						if ($result eq "-1") {
							print "Error: Attribute \"$attribute\" not found in instrumentation class \n";
						}
						else {
							if (isfloat($result)) {
								$result = sprintf("%.2f", $result);
							}
							print $result;
						}
					}
				}
				else {
					if (isfloat($result)) {
						$result = sprintf("%.2f", $result);
					}
					print $result;
				}
			}
		}
	}
}
else {

	foreach my $inst ($devObj->$get_method()) {
		# -- get object of instance
		$iObj = eval { $session->object($inst); };
		if ($@) {
			print "Error: Unable to get object of \"$inst\"\n";
			next;
		} else {
			next if ($iObj->isNull());
			next if (!$iObj->{IsManaged});
			
			my $class = $iObj->{CreationClassName};
			my $key = $instrumentation_keys{$class};
			
			if ($ARGV[2] eq "index") {
				print $iObj->{DeviceID}, "\n";
				
			# -- get instance count
			} elsif ($ARGV[2] eq "num_indexes") {
				$count++;
				
			# -- return result of get command (e.g: perl ionix_generic_query.pl "apm:Router:example.domain.com" Interface get Type <DeviceID>)
			} elsif ($ARGV[2] eq "query") {
				
				my $result =  eval { $iObj->get($ARGV[3]); };
				if ($@) {
					
					# -- if attribute not exists in Main class (Interface) try to get it from Instrumentation class
					if ($debug) { print "Debug: Attribute \"$ARGV[3]\" not exists in class $iObj->{CreationClassName}\n"; }
					
					# -- if current class has Instrumentation Key then check attribute in Istrumentation class
					if ($key) {
						my $result = check_instrumentation($key, $iObj, $ARGV[3]);
						if ($result eq "-1") {
							if ($debug) { print "Error: Attribute \"$ARGV[3]\" not found in instrumentation class \n"; }
							next;
						}
						else {
							print "$iObj->{DeviceID}:-:$result\n";
						}
					}
				}
				else {
					print "$iObj->{DeviceID}:-:$result\n";
				}
				
			}
		}
	}
}

if ($ARGV[2] eq "num_indexes") {
	print "$count\n";
}

sub help {
	print "Usage:\n\n";
	print "./$0 <hostname> <pattern_class_name> index\n";
        print "./$0 <hostname> <pattern_class_name> num_indexes\n";
        print "./$0 <hostname> <pattern_class_name> query {attribute1, attribute2...}\n";
        print "./$0 <hostname> <pattern_class_name> get {attribute1, attribute2...} DEVICE\n";
}

sub check_instrumentation {
	my ($key, $iObj, $attribute) = @_;
	
	$instr = $iObj->findInstrumentation($key);
	if ($instr ne "") {
		my $instr_obj = eval { $session->object($instr); };
		if ($@) {
			print "Error: Can not get object of  \"$instr\"\n";
		}
		else {
			my $value = eval { $instr_obj->get($attribute) ; };
			if ($@) {
				return "-1";
			}
			else {
				return $value;
			}
		}
	}
	else {
		return "-1";
	}
	
} # -- check_instrumentation

sub isfloat {
	my $val = shift;
	return $val =~ m/^\d+.\d+$/;
} # -- isfloat
	
