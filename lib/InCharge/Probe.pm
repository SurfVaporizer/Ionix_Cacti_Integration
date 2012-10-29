# ---------------------------------------------------------------------
#
# InCharge support for Perl probes
#
# Copyright 1996-2005 by EMC Corporation ("EMC").
# All rights reserved.
# 
# UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
# copyright notice above does not evidence any actual or intended
# publication of this software.  Disclosure and dissemination are
# pursuant to separate agreements. Unauthorized use, distribution or
# dissemination are strictly prohibited.
#
# ---------------------------------------------------------------------
# Packet interface and settings {{{

package InCharge::Probe;

use strict;
use warnings;
use 5.006_001;
use POSIX;

our $VERSION = '1.0';

use Exporter;

use InCharge::session;
use Carp qw(croak carp);

use vars qw( 
		@ISA 
		@EXPORT
		@EXPORT_OK 
	   );
	   
@ISA = ('Exporter');

@EXPORT = qw();
# }}}

# ---------------------------------------------------------------------
# the works {{{

my $__probe;
my $__server;
my $__params;
my $__sess;
my $__errmsg = undef;
my $__rc = 0;

my $__result;
my $__changed;
my $__discoveryError;
my $__objectName;

my $DOWARN = 0;

my $fields = {
	session		=> undef,
	elementName	=> undef,
	elementType	=> undef,

	ga_params	=> undef,

	hist_accessor	=> undef,
	integ_accessor	=> undef,
	jmx_accessor	=> undef,
	os_accessor	=> undef,
	remote_repos_accessor => undef,
	snmp_accessor	=> undef,

	TopologyManager	=> undef,
	AppFactory	=> undef,
	AppObjFactory	=> undef,
	LocalHost	=> undef,
	LocalService	=> undef,

	trace		=> undef,
	};


sub new {
	croak "Only one probe instance allowed" if $__probe;

	my $that = shift;
	my $class = ref($that) || $that;
	my $self = { %$fields };
	bless $self, $class;

	$self->__init();

	$__probe = $self;
	return $self;
	};


sub get {
	return &new unless $__probe;
	return $__probe;
	}


sub DESTROY { }


sub __exit {
	if ($__errmsg) {
		# this adds to the server log
		print STDOUT
			($__rc ?  "Probe error: " : "Probe warning: ");
		print STDOUT $__errmsg."\n";
		}
	undef $__errmsg;
	exit($__rc);
	}


sub error {
	my $self = shift;
	$__errmsg = shift;
	$__rc = -1;
	#print STDERR "-e> rc = $__rc\n";
	}


sub setWarning { $DOWARN = 1; };

sub warn {
	my $self = shift;
	$__errmsg = shift;

	warn($__errmsg);

	#print STDERR "-w> rc = $__rc\n";
	}


sub stop {
	my $self = shift;
	$__errmsg = shift;
	$__rc = -1 if $__errmsg;
	#print STDERR "-s> rc = $__rc\n";
	&__exit;
	}


sub singleton ($) {
	my $class = shift;

	my @instances = $__sess->getInstances($class);
	return $__sess->object($instances[0]);
	}


sub getObject ($$$) {
	my ($self, $class, $inst) = @_;
	my $obj;

	if (defined($inst)) {
		eval {
			$obj = $__sess->object($class, $inst);
			$obj = $__sess->create($class, $inst)
				  unless $obj->{Name};
		};
	} else {
		eval {
			$obj = $__sess->object($class);
			$obj = $__sess->create($class)
				unless $obj->{Name};
		};
	}

	croak $@." class $class" if $@;

	return $obj;
	}


sub createObject () {
	my ($self, $classinst, $inst) = @_;
	return $__sess->create($classinst, $inst) if $inst;
	return $__sess->create($classinst);
	}


sub checkObject () {
	my ($self, $classinst, $inst) = @_;
	return $__sess->object($classinst, $inst) if $inst;
	return $__sess->object($classinst);
	}

sub getElementObjectName {
	return $__objectName;
	}

sub setElementObjectName ($$) {
	my ($self, $name) = @_;
	my ($thename);

	croak("Probe uninitialized")
		unless $self->{ga_params};

	if (ref($name) eq "InCharge::object" ) {
		$thename = $name->{"_instance"};
		}

	if (! ref($name) ) {
		my ($theobj) = $self->checkObject($name);
		if (defined($theobj)) {
			$thename = $theobj->{"_instance"};
			}
		}
	$thename = $name unless defined($thename);
	$__objectName = $thename;
	}

sub getProbeResult {
	return $__result;
	}

sub setProbeResult ($) {
	my ($self,$value) = @_;

	croak("Probe uninitialized")
		unless $self->{ga_params};

	$value = "FAILED" if ! defined($value) or ! $value;
	$value = "SUCCESS" if defined($value) and $value == 1;
	$__result = $value;
	}

sub getDiscoveryError {
	return $__discoveryError;
	}

sub setDiscoveryError ($) {
	my ($self,$value) = @_;
  
	croak("Probe uninitialized")
		unless $self->{ga_params};

	$__discoveryError = $value;
	}

sub getChanged {
	return $__changed;
	}

sub setChanged ($) {
	my ($self,$value) = @_;
  
	croak("Probe uninitialized")
		unless $self->{ga_params};

	$value = "FALSE" if ! defined($value) or ! $value;
	$value = "TRUE" if defined($value) and $value == 1;
	$__changed = $value;
	}

sub getIARuntimeParams ($$$) {
	my ($self, $object, $action) = @_;

	unless ($self->{integ_accessor}) {
		$self->{integ_accessor} = &singleton("IntegAccessorInterface");
		}

	# will throw exception if no accessor or create fails
	return $__sess->object(
		$self->{integ_accessor}->getRuntimeParams($object, $action)
		);
	}

sub createIARuntimeParams ($$$) {
	my ($self, $object, $action) = @_;

	unless ($self->{integ_accessor}) {
		$self->{integ_accessor} = &singleton("IntegAccessorInterface");
		}

	# will throw exception if no accessor or create fails
	return $__sess->object(
		$self->{integ_accessor}->getRuntimeParams($object, $action)
		);
	}

sub dehex {
	my $str = shift;
	my $len = (length $str) / 2;
	my $out = "";

	for (my $i = 0; $i < $len; $i++) {
		$out = $out.chr hex substr $str, $i * 2, 2;
		}

	return $out;
	}

sub __init ($) {
	my $self = shift;

	#print STDOUT "server=$__server\n";
	unless ($__server =~ /^--server=([-\w.]+)\:(\d+)\/([-\w]+)/) {
		croak("No server name given.");
		}

	my $Host	= $1;
	my $Port	= $2;
	my $Domain	= $3;
	my $Timeout	= 120;
	my $Trace	= 0;

	# essentials
	eval {
		my %special = (
			"result" => \$__result,
			"changed" => \$__changed,
			"objectName" => \$__objectName,
			"discoveryError" => \$__discoveryError,
			);

		#
		# acquire the parameters
		#
		$self->{ga_params} = ();	# new hash
		while (<STDIN>) {
			last if /EOF/;
			next unless /^(\w+)=(\w+)/;

			if ($special{$1}) {
				${$special{$1}} = &dehex($2);
				}
			else {
				$self->{ga_params}{$1} = &dehex($2);
				}
			}

		#
		# actually only needed for probes that need to update the topology
		#
		$__sess = $self->{session} = InCharge::session->new(
			broker          => "",
			server          => "$Host:$Port/$Domain",
			timeout         => $Timeout,
			traceServer     => $Trace
			);

		my ($appFclass, $appFinst);
		$appFclass = $self->{ga_params}{"factoryClassName"};
		$appFinst = $self->{ga_params}{"factoryInstanceName"};
		my ($appfactory);


		eval {
        	if ( defined($appFclass) and defined($appFinst) and $appFclass and $appFinst ) {
          		$appfactory = $__sess->object($appFclass,$appFinst);
        		} 
        	if ( ! defined($appfactory) ) {
          		$appfactory = &singleton("Application_ObjectFactory");
        		}
	    	if ( defined($appfactory)) {
          		$self->{AppFactory} = $appfactory;
          		$self->{AppObjFactory} = $appfactory;
          		$self->{LocalHost}  = $appfactory->findLocalHost();
          		$self->{LocalService} = $appfactory->findLocalService();
        		}
		};
		$self->warn("$@") if $@;	


		$self->{elementName} = $self->{ga_params}{"elementName"};
		$self->{elementType} = $self->{ga_params}{"elementType"};

		$self->{TopologyManager} = &singleton("ICF_TopologyManager");

		$self->{hist_accessor} = $__sess->object(
						"MR_AccessorInterface",
						"HistoryOnlyAccessor"
						);
		$self->{remote_repos_accessor} = $__sess->object(
						"MR_AccessorInterface",
						"MR-RemoteReposInterface"
						);
		};
	croak("$@") if $@;

	# optional, sort of
	eval { $self->{integ_accessor}	= &singleton("IntegAccessorInterface"); };
	eval { $self->{jmx_accessor}	= &singleton("JMXAccessorInterface"); };
	eval { $self->{os_accessor}	= &singleton("OSAccessorInterface"); };
	eval { $self->{snmp_accessor}	= &singleton("SNMP_AccessorInterface"); };

	carp("Warning: no accessor found - $@") unless
		$self->{integ_accessor}	||
		$self->{jmx_accessor}	||
		$self->{os_accessor}	||
		$self->{snmp_accessor}
		;

	undef $@; 
	}

BEGIN	{
	$__server = $main::ARGV[0];
	$__params = $main::ARGV[1];	# FIXME: this arg is now useless
	$SIG{'__WARN__'} = sub { warn $_[0] if $DOWARN };

	# Defaults should indicate that the probe has not yet run,
	# in case anything goes wrong early in the probe proper.
	$__result		= "FAILED";
	$__changed		= "FALSE";
	$__objectName		= "";
	$__discoveryError	= "Probe ready to run";
	}

END	{ 
	#
	# perl stdout not flushing even on normal exit <sigh>
	#
	select STDOUT; $| = 1;

	my ($exit_code,$reason, $errmsg);
	$exit_code = 0;

	if ($? >> 8) { 
		$reason = "\$\?"; 
		$exit_code = ($? >> 8);
		$errmsg = "Child process exited with status $exit_code ($reason)";
	}
	if ($@) {
		$exit_code = -1;
		$errmsg = "Caught exception: $@";
	} 
	if (defined($exit_code) and $exit_code ) {
		$__discoveryError = "" unless defined $__discoveryError;
		$__discoveryError .= " ".$errmsg;
		$__result = "FAILED";
	}

	#
	# Each line of output is interpreted as an assignment or log message
	# by the calling routine in TM. This is a best-effort - if perl dies
	# abnormally, the TM will grab whatever it gets on stdout & stderr,
	# and report failed status.
	#
	print "result ".$__result."\n";
	print "changed ".$__changed."\n";
	print "discoveryError ".$__discoveryError."\n";
	print "objectName ".$__objectName."\n";

	&POSIX::_exit($exit_code);
	}

1;
# }}}

# ---------------------------------------------------------------------
__END__
# Documentation {{{

=head1 NAME

	InCharge::Probe

=head1 SUMMARY

	Support library for InCharge discovery probe scripts in Perl

=head1 COPYRIGHT

 Copyright 1996-2005 by EMC Corporation ("EMC").
 All rights reserved.
 
 UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
 copyright notice above does not evidence any actual or intended
 publication of this software.  Disclosure and dissemination are
 pursuant to separate agreements. Unauthorized use, distribution or
 dissemination are strictly prohibited.

=head1 SYNOPSIS
	
	use InCharge::Probe;

	my $probe = InCharge::Probe->new;

=head1 DESCRIPTION

	
=head2 Data

	Each of these can be accessed as I<$probe->{datum}>.

=item B<session>

	Server remote API session, initialized by B<new>.

=item B<elementName>, B<elementType>

	These are inputs to the probe script set by the Topology Manager.

=item B<ga_params>

	Parameters for the probe script invocation, includes the
	element name and type inputs, and the object name output
	(see method B<setObjectName> below).

=item B<hist_accessor>
=item B<integ_accessor>
=item B<jmx_accessor>
=item B<os_accessor>
=item B<remote_repos_accessor>
=item B<snmp_accessor>

	Miscellaneous accessor objects, which are initialized to the
	respective accessor objects in the repository at the start of
	the script. Note that only accessors that are present are
	initialized, and the others will be left in undefined state.
	At least two accessors are expected (or the script will print
	a warning.

=item B<TopologyManager>
=item B<AppFactory>
=item B<LocalHost>
=item B<LocalService>

	Automatically initialized references to objects useful in
	a discovery probe.

=head2 Methods

=item B<get>

	Returns reference to the already initialized probe object.
	Will silently invoke B<new> to create one.

=item B<error> (message)

	Saves the message to be eventually returned to the InCharge
	server with an error return status when the script terminates.
	The error status is returned even if the message is undefined.

=item B<stop> ([message])

	Stops execution of the script.
	If a message argument is given, it will be treated as
	short for calling I<error(message)> followed by I<stop()>,
	i.e. an error status is returned to the server.

	If no message argument is given, the script execution
	will be simply stopped. If B<error> had been called already,
	an error status will be returned to the server.

=item B<warn> (message)

	Sets the message to be returned to the server when the
	script execution completes. If undefined, the message will
	get cleared. Does not set or clear the error status that
	will be returned. 

	The function also sends the same error message to the 
	I<warnings::warn()> to handle warning signals. 

=item B<new>

	Creates and initializes an InCharge Perl probe object.
	Only one instance is allowed, so a second call to B<new>
	will fail with an error message.

=item B<singleton> (class)

	Returns the class instance. Does not flag if there's more
	than one. 

=item B<checkObject> (class[,instance])

	Gets an existing object of the given class and instance names.
	If only one argument given, it's expected to be a string
	of the class::instance form.

=item B<getObject> (class[,instance])

	Same as B<checkObject>, except, if an object of this name
	doesn't exist in the repository, one will be created and returned.

=item B<createObject> (class[,instance]#)

	Creates an object of this class::instance name. Will return
	error if there's already one.

=item B<setElementObjectName> (name)

	Updates GA_PARAMS with the (new) objectName.
	Convenience method for discovery probes.

=item B<setDiscoveryError> (name)

	Updates GA_PARAMS with discovery error message.
	Convenience method for discovery probes.

=item B<setResult> (name)

	Updates GA_PARAMS with the status of probing.
	Valid values are SUCCESS or FAILED.
	Convenience method for discovery probes.

=item B<setChanged> (name)

	Updates GA_PARAMS to notify whether topology was changed or not.
	Valid values are TRUE or FALSE.
	Convenience method for discovery probes.

=item B<getElementObjectName>

	Get current value of the objectName in GA_PARAMS.
	Convenience method for discovery probes.

=item B<getDiscoveryError>

	Get current discovery error message value in GA_PARAMS.
	Convenience method for discovery probes.

=item B<getResult>

	Get current value of the probing status in GA_PARAMS.
	Convenience method for discovery probes.

=item B<getChanged>

	Gets current value of changed flag from GA_PARAMS.
	Convenience method for discovery probes.

=item B<getIARuntimeParams> (object, action)

	Creates a I<Runtime_Params> object intimately bound to
	both the monitored object and the monitoring action object.
	This is preferred because, among other things, the monitored
	object can be then connected to the Integration Accessor by
	simply invoking the I<connect> method on the returned
	runtime parameters object.

=head1 MODULE DEPENDENCIES

	Exporter
	Carp

=head1 AUTHOR

	(patterw@smarts.com)
	(guruprv@smarts.com)

=cut

# }}}

# ---------------------------------------------------------------------
# vim:set fdm=marker:
