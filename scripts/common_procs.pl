#!/usr/bin/perl
# -- Author: Skribnik Evgeniy
# -- This program is free software; you can redistribute it and/or
# -- modify it under the terms of the GNU General Public License
# -- as published by the Free Software Foundation;

# -- Description: Common procedures

# -- ChangeLog
# -- Version: 0.1b

use utf8;

# -- common procedures


sub print_log {
	my ($context, $text) = @_;
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
	$year = $year+1900;
	$year = "$year";
	$mon = $mon+1;
	$mon = sprintf("%02d", $mon);
	$mday = sprintf("%02d", $mday);
	$hour = sprintf("%02d", $hour);
	$min = sprintf("%02d", $min);
	$sec = sprintf("%02d", $sec);
	
	if ($log_dir eq "") {
		$log_dir = $confHash{'global.log_dir'};
	}
		
	if (($log_policy eq "file") ||($log_policy eq "both")) {
		open (F_LOG,">>:utf8", $log_dir."/".$log_file_name_template."_".$year.".".$mon.".".$mday.".log");
		print F_LOG "$year.$mon.$mday $hour:$min:$sec ".$context." ".$text."\n";
		close (F_LOG);
	}
	if (($log_policy eq "stdout")||($log_policy eq "both")){
	print "$year.$mon.$mday $hour:$min:$sec ".$context." ".$text."\n";
	}
} # -- print_log

sub xArray2Hash {
	my ($ref, $key_field) = @_;
	my @tmpArr = @$ref;
	
	foreach (@tmpArr) {
		my %tmp = %$_;
		foreach my $k (keys %tmp) {
			$hash{$tmp{$key_field}}{$k} = $tmp{$k}; 
		}
	}
	return %hash;
} # -- xArray2Hash

sub load_config {
	my ($profile_cfg) = @_;
	
	my %Config = ();
	
	# -- read config file
	$cfg = new Config::Simple($profile_cfg);
	# -- parse config file
	%Config = $cfg->vars();
	return %Config;
} # -- load_config

# -- Ionix procedures
sub dmConnect {
	my ($broker, $manager, $username, $password, $description) = @_;
	
	if ($description eq "") {
		$description = "Connect by \"Cacti\"";
	}
	$session = InCharge::session->new(
		broker=>$broker,
		domain=>$manager,
		username=>$username ,
		password=>$password,
		timeout=>'5',
		description=> $description,
		traceServer => 0
	);
	return $session;
} # -- dmConnect

sub checkSmValue {
	my ($obj, $value) = @_;
	my $result;
	
	$result = eval{$obj->get("$value");
	};
	if ( $@ ) {
		# print "Error obtaining the $value property<br>";
		return "-1";
	} else {
		# print "$value is $result<br>";
		return 1;
	}

} # -- checkSmValue

sub getSmValue {
	my ($obj, $value) = @_;
	my $result;
	
	$result = eval{$obj->get("$value");
	};
	if ( $@ ) {
		print"Error:", "Can not get object of  \"$obj\"";
		return "-1";
	} else {
		if (!$obj->isNull()) {
			return $result;
		} else {
			return "-1";
		}
	}

} # -- getSmValue

# -- Database procedures

sub dbConnect {
	my ($user, $pass, $db, $host, $port, $type) = @_;
	my $dsn = "DBI:$type:database=$db;host=$host;port=$port";
	my $dbh = DBI->connect($dsn, $user, $pass, {mysql_enable_utf8 => 1}) ||
		die "Could not connect to database: $DBI::errstr";
		if ($DBI::errstr eq "") {
			$dbh->{'mysql_enable_utf8'} = 1;
			$dbh->do('SET NAMES utf8');
			return $dbh;
		}
		else {
			return "Could not connect to database: $DBI::errstr";
		}
} # -- dbConnect

sub get_table_hasharr_by_sql {
	my ($query)=@_;
	my @temp;
	my $sth = $dbh->prepare($query);$sth->execute();
	if ($DBI::errstr){
		print_log("error", "Unable to execute SQL ($query): ".$DBI::errstr);
		return \@temp;
	}
	while (my $refe = $sth->fetchrow_hashref()){
		my %hash=%$refe;
		
		foreach my $key (keys %hash) {
			$hash{$key} = $value;
		}
			
		push (@temp,\%hash);
	}
	$sth->finish();
	return \@temp;
} # -- get_table_hasharr_by_sql


sub xGet_table_hasharr_by_sql {
	my ($query)=@_;
	my @temp;
	my $sth = $dbh->prepare($query);$sth->execute();
	if ($DBI::errstr){
		print_log("error", "Unable to execute SQL ($query): ".$DBI::errstr);
		return \@temp;
	}
	while (my $refe = $sth->fetchrow_hashref()){
		my %hash=%$refe;
		
		foreach my $key (keys %hash) {
			$value = Encode::decode('UTF-8',$hash{$key});
			$hash{$key} = $value;
		}
			
		push (@temp,\%hash);
	}
	$sth->finish();
	return \@temp;
} # -- xGet_table_hasharr_by_sql

sub exec_sql {
	my ($sql)=@_;
	my $sth = $dbh->prepare($sql);
	if ($DBI::errstr){
		$errMsg = "Unable to prepare SQL ($query): ".$DBI::errstr;
		return "-1";
	}
	$sth->execute();
	if ($DBI::errstr){
		$errMsg = "Unable to prepare SQL ($query): ".$DBI::errstr;
		return "-1";
	}
	$sth->finish();
} # -- exec_sql

sub xGet_hash_by_sql {
	my ($query) = @_;
	my @temp;
	my %tempout = ();
	my $sth = $dbh->prepare($query);
	$sth->execute();
	
	if ($DBI::errstr){
		$errMsg = "Unable to execute SQL ($query): $DBI::errstr";
		return %tempout;
	}
	while (my $refe = $sth->fetchrow_hashref()) {
		my %hash = %$refe;
		
		 foreach my $key (keys %hash) {
			 $value = Encode::decode('UTF-8',$hash{$key});
			 $hash{$key} = $value;
		 }
		
		push (@temp, \%hash);
	}
	$sth->finish();
	if ((scalar @temp) ne 1 ){
		return %tempout;
	}
	%tempout = %{$temp[0]};
	return %tempout;
} # -- xGet_hash_by_sql

1;
