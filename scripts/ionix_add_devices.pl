#!/usr/bin/perl
# -- Author: Skribnik Evgeniy
# -- This program is free software; you can redistribute it and/or
# -- modify it under the terms of the GNU General Public License
# -- as published by the Free Software Foundation;

# -- Description: Import devices from Ionix to Cacti

# -- ChangeLog
# -- Version: 0.1b

BEGIN {
	# -- insert cacti path to "cacti_path" variable
	our $cacti_path = "/var/www/html/cacti/";
	our $integration_path = $cacti_path."ionix_integration/";
	our $lib_path = $integration_path."lib/";
	our $lib_perl_path = $integration_path."lib/lib/perl5";
	our $log_dir = $integration_path."/logs/";
	our $conf_file = $integration_path."main.cfg";
}
# -- Import ionix Perl API library
use lib $lib_path;
use lib $lib_perl_path;

use utf8;
use DBI;
use Getopt::Long;
use InCharge::session;
use Encode;
use v5.8.8;

# -- required modules
use Config::Simple;
use Data::Dumper;


# -- Import common procedures file
require "$integration_path/scripts/common_procs.pl";

# -- load global configuration file
%confHash = ();
%confHash =  load_config($conf_file);

# -- ionix credentials
my $sm_username = $confHash{'ionix.sm_username'};
my $sm_password = $confHash{'ionix.sm_password'};
my $broker = $confHash{'ionix.broker'};

# -- cacti database variables
my $db_username = $confHash{'cacti.db_username'};
my $db_password = $confHash{'cacti.db_password'};
my $db_name = $confHash{'cacti.db_name'};
my $db_host = $confHash{'cacti.db_host'};
my $db_port = $confHash{'cacti.db_port'};
my $db_type = $confHash{'cacti.db_type'};

# -- exclude|include config
my $mgr_exclude_list = $confHash{'global.mgr_exclude_list'};
my $mgr_include_list = $confHash{'global.mgr_include_list'};

my $device_include_pattern = $confHash{'global.device_include_pattern'};

# -- get list of sam managers from config
my $ref = $cfg->param(-block=>'sam_list');
my %sam_list_hash = %$ref; 

# -- get list of cacti host templates by ionix class name
my $ref = $cfg->param(-block=>'templates');
my %host_templates = %$ref;

# -- global variables
my $debug = $confHash{'global.debug'};

# -- log file variables
$log_file_name_template = "import";
$log_policy = "both";

# -- possible commands
# -- 1. import - Import devices from defined in configuratoin file (sam_list) SAM managers
my $import_flag = undef;
my $help = undef;
my $clear_flag = undef;
my $force_flag = undef;

if ( @ARGV > 0 ) { GetOptions ("help|?" => \$help, "force" => \$force_flag) or usage(); }
if ($ARGV[0] eq "import") {
	$import_flag = 1;
}
elsif ($ARGV[0] eq "clear") {
	$clear_flag = 1;
}
else {
	usage();
}

if ($debug) { print_log("Debug:", "Start $0 with parameters \"@ARGV\""); }

if ($import_flag) {
	import_hosts($force_flag);
}

if ($clear_flag) {
	clear_hosts();
}

sub clear_hosts {
	# -- connect to DB
	print_log("Info:", "Connecting to DB $db_name with credentials \"$db_username, $db_password,\"");
	$dbh = dbConnect($db_username, $db_password, $db_name, $db_host, $db_port, $db_type);
	
	# -- get count of devices with no data source or graphs related
	
	my $sql = "select count(hostname) as count from host where host.id not in (select host_id from poller_item)";
	
	my %result = xGet_hash_by_sql($sql);
	if ($errMsg) {
		print_log("Error:", $errMsg);
		exit;
	}
	
	my $count = $result{count};
	
	my $sql = "delete from host where host.id not in (select host_id from poller_item)";
	
	my $val = exec_sql($sql);
	if ($errMsg) {
		print_log("Error:", $errMsg);
		exit;
	}
	else {
		if ($debug) { print_log("Debug:", "delete process successfully completed for \"$count\" devices"); }
	}
		
	exit;
} # -- clear_hosts


sub import_hosts {
	my ($force_flag) = @_;
	
	# -- connect to cacti database
	# -- connect to DB
	print_log("Info:", "Connecting to DB $db_name with credentials \"$db_username, $db_password,\"");
	$dbh = dbConnect($db_username, $db_password, $db_name, $db_host, $db_port, $db_type);
	
	my $sql = "select hostname, id from host";
	
	my $ref = xGet_table_hasharr_by_sql($sql);
	my %cacti_hosts = xArray2Hash($ref, "hostname");
	
	my $sql = "select * from host_template";
	my $ref = xGet_table_hasharr_by_sql($sql);
	my %cacti_host_templates = xArray2Hash($ref, "name");
	
	
	# -- get sam managers from "sam_list" block in configuration file
	foreach my $k (keys %sam_list_hash) {
		next if  $k eq "";
		my $broker = $sam_list_hash{$k};
		my $sam_manager = $k;
		
		# -- connect to each SAM via defined broker
		my $session = eval { dmConnect($broker, $sam_manager, $sm_username, $sm_password); };
		if ($debug) { print_log("Debug:", "Connect to ionix manager \"$sam_manager\""); } 
		if ($@) {
			print_log("Error:", "$@\n");
			if ($debug) { print_log("Debug:", "Connect to next manager"); }
			next;
		}
		
		my @avail_src_domains = ();
		my %src_dm_props = ();
		if ($debug) { print_log("Debug:", "Get AM-PM managers from all connected domain managers"); }
		
		foreach my $k ($session->getInstances("InChargeDomain")) {
			my $dm_obj = $session->object($k);
			my $domain_name = $dm_obj->{DomainName};
			
			# -- fileter source managers by exclude|include list
			if ($mgr_include_list ne "") {
				if (!($domain_name =~ m/$mgr_include_list/ig)) {
					if ($debug) { print_log("Debug:", "SKIP, Manager \"$domain_name\" is not included to mgr_include_list filter"); }
				next;
				}
			}
			elsif ($mgr_exclude_list ne "") {
				if ($domain_name =~ m/$mgr_exclude_list/ig) {
					if ($debug) { print_log("Debug:", "SKIP, Manager \"$domain_name\" is defined in mgr_include_list filter"); }
					next;
				}
			}
			
			if ($debug) { print_log("Debug:", "Connect to ionix manager \"$domain_name\""); }
			
			# -- connect to InChargeDomain and check if current domain manager is AM-PM software
			my $src_session = eval { dmConnect($broker, $domain_name, $sm_username, $sm_password); };
			if ($@) {
				print_log("Error:", "$@");
				next;
			}
			# -- check if class exists 
			if ($src_session->classExists("InCharge_Devstat_Feature") && $src_session->classExists("InCharge_Performance_Feature") && $src_session->classExists("InCharge_Discovery_Feature") ) {
				push(@avail_src_domains, $dm_obj->{Name});
				$avail_src_apm_labels{$dm_obj->{Name}} = $dm_obj->{DomainName};
			}
			undef $src_session;
		}
		foreach my $k ($session->getInstances("ICIM_UnitaryComputerSystem")) {
			
			# -- get object
			my $dev_obj = eval { $session->object($k); };
			if ($@) {
				if ($debug) { print_log("Error:", "Can't get object to device \"$k\" from manager \"$sam_manager\""); }
			}
			next if ($dev_obj->isNull());
			next if (!$dev_obj->{IsManaged});
			
			my $device_name = $dev_obj->{DisplayName};
			
			# -- filter devices by device_include_pattern variable
			if ($device_include_pattern ne "") {
				if (!($device_name =~ m/$device_include_pattern/ig)) {
					if ($debug) { print_log("Debug:", "SKIP, Device \"$device_name\" ignored by device_include_pattern"); }
					next;
				}
			}
			
			# -- get source domain name for current devices
			my $apm_name = "";
			my @dm_list = $dev_obj->get("MemberOf");
			
			foreach (@avail_src_domains) {
				if (grep(/$_/, @dm_list)) {
					$apm_name = $avail_src_apm_labels{$_};
				}
			}
			
			if ($apm_name eq "") {
				if ($debug) { print_log("Debug:", "APM manager not defined for device \"$device_name\""); }
				next;
			}
			
			# -- create uniq string for compare with cacti field
			# -- <Broker:Port>::<SAM>::<APM>::<Class>::<Name>
			
			my $uniq_string = $broker."::".$sam_manager."::".$apm_name."::".$dev_obj->{CreationClassName}."::".$device_name;
			
			my $cacti_template_id = "";
			if (defined($host_templates{$dev_obj->{CreationClassName}})) {
				my $template_name = $host_templates{$dev_obj->{CreationClassName}};
				if (defined($cacti_host_templates{$template_name}->{id})) {
					$cacti_template_id = $cacti_host_templates{$template_name}->{id};
				}
				if ($debug) { print_log("Debug:", "Host template id for device \"$dev_obj->{DisplayName}\" = \"$cacti_template_id\""); }
			}
			
			# -- compare if current device exists in cacti
			if (defined($cacti_hosts{$uniq_string})) {
					if ($debug) { print_log("Info:", "SKIP, Device \"$dev_obj->{DisplayName}\" is defined in cacti with id \"$cacti_hosts{$uniq_string}->{id}\", skip.."); }
					# -- force add device if --force flag is defined
					if ($force_flag) {
						add_device($uniq_string, $dev_obj->{DisplayName}, $cacti_template_id);
					}
			}
			else {
				if ($debug) { print_log("Info:", "Device \"$dev_obj->{DisplayName}\" is NOT defined in cacti"); }
				
				
				# -- set cacti host template id to current device
				
				# -- add device
				add_device($uniq_string, $dev_obj->{DisplayName}, $cacti_template_id);
			}
		}
		undef @avail_src_domains;
		undef %avail_src_apm_labels;
		
	}
} # -- import_hosts

sub add_device {
	my ($host_ip, $host_description, $host_template_id) = @_;
	
	# -- example of add_device cli commands
	# -- php add_device.php --description="example.domain.com" --ip=localhost:426::apm:Router:example.domain.com --template=9 --avail=none
	my $cmd = "php $cacti_path". "cli/add_device.php --description=\"$host_description\" --ip=\"$host_ip\" --template=$host_template_id --avail=none";
	run_cmd($cmd);
} # -- add_device

sub run_cmd {
	my ($cmd) = @_;
	if ($debug) { print_log("Debug:", "Run command \"$cmd\"") ; }
	# -- run command
	my $cmd_out = eval {  `$cmd` };
	if ($@) {
		print_log("Error:", $@);
	}
	else {
		print_log("Debug:", $cmd_out);
	}
	
} # -- run_cmd
	


sub usage {
	print "Usage: $0 <command> (<option>)\n";
	print "Commands:\n";
	print "\timport -  import devices from ionix to cacti\n";
	print "\tclear -  delete devices with no assiciated ds or graphs\n";
	print "Options:\n";
	print "\t--force - Force import devices to cacti\n";
	exit;
}
