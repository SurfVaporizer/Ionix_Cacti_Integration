# ---------------------------------------------------------------------
#
# InCharge support for monitoring using Perl
#
# Copyright 2004-2005 by EMC Corporation ("EMC").
# All rights reserved.
# 
# UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
# copyright notice above does not evidence any actual or intended
# publication of this software.  Disclosure and dissemination are
# pursuant to separate agreements. Unauthorized use, distribution or
# dissemination are strictly prohibited.

# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-accessor/perl/Monitoring.pm#1 $
#
# ---------------------------------------------------------------------
# Packet interface and settings {{{

package InCharge::Monitoring;

=head1 NAME

	InCharge::Monitoring -
	Perl-based monitoring support for SMARTS InCharge servers.

=head2 COPYRIGHT

 Copyright 1996-2005 by EMC Corporation ("EMC").
 All rights reserved.
 
 UNPUBLISHED CONFIDENTIAL AND PROPRIETARY PROPERTY OF EMC.  The
 copyright notice above does not evidence any actual or intended
 publication of this software.  Disclosure and dissemination are
 pursuant to separate agreements. Unauthorized use, distribution or
 dissemination are strictly prohibited.


=cut

use strict;
use warnings;
use 5.006_001;

our $VERSION = '1.0';

use Carp qw(croak carp);
use Exporter;

use InCharge::Attribute;
use InCharge::MonitoredObject;
use InCharge::ParamGroupSet;
use InCharge::ParamGroup;

use vars qw( 
		@ISA 
		@EXPORT
		@EXPORT_OK 
		$SM_PARAMETER
		$SM_OBJECT
		$SM_ATTRIBUTE
		$SM_INSTRUMENT
		$SM_TIMEOUT
	   );
	   
@ISA = ('Exporter');

@EXPORT = qw(
		$SM_PARAMETER
		$SM_OBJECT
		$SM_ATTRIBUTE
		$SM_INSTRUMENT
		$SM_TIMEOUT
             );
@EXPORT_OK = qw(
		get
		setDebug
		setVerbose
		);

=head1 SYNOPSIS

	use InCharge::Monitoring;

	InCharge::Monitoring->setDebug;
	InCharge::Monitoring->setVerbose;

	my $monitor = InCharge::Monitoring->new;
	 -- OR --
	my $monitor = InCharge::Monitoring->get;

    my $pGroup = $monitor->groupObjectByParameter( 
                            # undef -> No default if not supplied
                            "hostname" => undef, 
                            # if port is not supplied use 25
                            "port"     => 25 );

    foreach $group ( $paramGroup->groups() ) {
         my $hostname = $group{parameters}{hostname};
         my $port     = $group{parameters}{port};

         # Common setup for grouping
         #
         my $sock = IO::Socket::INET->new(
                                   PeerAddr => $hostname,
                                   PeerPort => $port,
                                   Proto => 'tcp'
                                  );

         $sock->getline(); # Read and ignore banner

         #
         # Individual object processing
         #
         foreach $obj ( $group->objects() ) {
              my $command = $theObj->{parameters}{command};

              # Do object instance specific actions
              #
              print $sock "$command\n";
              $line = $sock->getline();
              $hasError =  ( $line =~ /^25/ ? 0 : 1);

              #
              # Report results back...
              $attrError = $obj->instruments{IsErrorSymptom};
              if ( defined($attrError) ) {
                 $attrError->setvalue();
              }
          }
          # Common cleanup for grouping
          $sock->close();
      }


    alternatively the following constructs are available

	my $value = $$SM_PARAMETER{$name};
	my $attr  = $$SM_ATTRIBUTE{$class."::".$inst."::".$attrib);
	my $attr  = $$SM_INSTRUMENT{$class."::".$inst."::".$attrib);
	my $obj   = $$SM_OBJECT{$class."::".$inst);
	my $tmout = $SM_TIMEOUT;

	my $param_hash	= $monitor->{parameters};
	my $object_hash	= $monitor->{objects};
	my $attrib_hash	= $monitor->{attributes};
	my $instrs_hash	= $monitor->{instruments};
	my $tmout       = $monitor->{timeout};

	foreach my $obj (sort values %$SM_OBJECT) { ... }
	foreach my $attr (sort values %$SM_ATTRIBUTE) { ... }
	... etc ...

=head1 DESCRIPTION

	The InCharge::Monitoring module enables objects defined in the
	InCharge repository to be monitored using Perl scripts.  It is
	independent of InCharge perlApi, which provides general access
	to InCharge servers.  The Monitoring module enables Perl scripts
	to update attributes of monitored objects under the control of
	the InCharge server model, which invokes these action scripts
	periodically according to polling interval parameters defined
	by the model.

	A monitoring script must be located in one of the following
	directories in an InCharge server:

		$SM_HOME/integration/
		$SM_HOME/local/integration/

	where SM_HOME is the InCharge installation directory.

	The script will then be invoked by the InCharge server provided:

	* the Integration Accessor has been instantiated in the server;

	* an instance of model class MA_PerlScript has been created
	  and initialized with the name of the script;

	* one or more model objects with attributes to be monitored
	  have been instantiated and connected to the Integration Accessor
	  using the MA_PerlScript instance as the action argument;

	  -- and --

	* there are active property or event subscriptions to the object.

=cut

# }}}

# ---------------------------------------------------------------------
# Class definition and methods {{{

my $__monitoring;
my $__debug = undef;
my $__verbose = undef;

my $fields = {
	parameters	=> undef,
	objects		=> undef,
	attributes	=> undef,
	instruments	=> undef,
	timeout		=> undef
	};

=head2 Data members

=over 4

=item B<{parameters}>

=item B<%$SM_PARAMETER>

	Hash table of key-value parameter strings set up in the (model)
	action object.

	These parameters are common to all invocations of that action,
	regardless of which objects and their attributes are being polled.
	Accessible through the monitoring interface object as

		$mon->{parameters}

	or directly as a global variable (polluting your namespace!)

		%$SM_PARAMETER


=item B<{objects}>

=item B<%$SM_OBJECT>

	Hash table of objects which need to be updated in this poll cycle.
	Keys are string-valued names of the form "$class::$instance".
	The values are references to L<MonitoredObject> data structures,
	each containing the following:

	* A list of object-specific parameters (defined in the
	  L<Runtime_Parameters> associated with the object).

	* The list of attributes belonging to that object that need to be
	  monitored, designated "instrumented" in L<MODEL> (for historical
	  reasons having to do with SNMP).

	* A list of "instruments", that is model-independent name strings,
	  corresponding to the attributes (see L<SM_INSTRUMENT> below).

	Accessible through the monitoring interface object as

		$mon->{objects}

	or directly as a global variable (polluting your namespace!)

		%$SM_OBJECT


=item B<{attributes}>

=item B<%$SM_ATTRIBUTE>

=item B<{instruments}>

=item B<%$SM_INSTRUMENT>

	Global hash table of all attributes requested for update by
	the server. That is, the attributes of all objects identified
	in %$SM_OBJECT are directly accessible through this table.

	Keys are strings of the form "$class::$instance::$attribute"
	in %$SM_ATTRIBUTE, where $attribute is the attribute name as
	defined in the model. Model-independent keys are provided in
	%$SM_INSTRUMENT in the form "$class::$instance::$instrument".

	The values are references to L<Attribute> data structures.
	Accessible through the monitoring interface object as

		$mon->{attributes} --OR-- $mon->{instruments}

	respectively, or directly as the global variables

		%$SM_ATTRIBUTE --OR-- %$SM_INSTRUMENT .


=item B<{timeout}>

=item B<$SM_TIMEOUT>

	If defined, denotes the total timeout for the Perl action set
	by the server.

	Implementing this timeout is left entirely to the monitoring
	script -- the script may ignore this setting altogether (and
	face getting timed out by the server with a corresponding error
	message in the log).

	An action script that wants to budget the time it spends for each
	object can look up the timeout value given in the corresponding
	L<MonitoredObject> data structure.

	The timeout given by $SM_TIMEOUT (or $mon->{timeout}) will be
	at least the sum of the object timeouts and a separate timeout
	setting on the action model object itself, the intent being that
	the action timeout


=back

=head2 Methods

=over 4

=item B<new>

	Static constructor method to create and initialize a Monitoring
	interface object. There can be only one Monitoring object (since
	a given action process would have exactly one InCharge server
	that invoked it). Method invocation:

		my $mon = InCharge::Monitoring->new;

	Will L<croak> if called more than once in an action process.

=cut

sub new {
	croak "Only one Monitoring instance allowed" if $__monitoring;

	my $that = shift;
	my $class = ref($that) || $that;
	my $self = { %$fields };
	bless $self, $class;

	$__monitoring = $self;
	&__init($self);

	return $self;
	};


=item B<get>

	Static constructor method to retrieve reference to existing
	Monitoring interface object. If it doesn't exist, the new
	method is silently called.  Invoked as

		my $mon = InCharge::Monitoring->new;

=cut

sub get {
	&new unless $__monitoring;
	return $__monitoring;
	}

=item B<groupObjectByParameter>
    
    Build and return an InCharge::ParamGroupSet instance which groups
    the objects to monitor based on the values of a set of paramaters.
    The arguments are the list of parameters to group on, given as
         "<name>" => <default_value>
    Where if <default_value> is undef objects without said parameter
    are not included.  
    If <default_value> is given for a parameter it is used in the case
    the probe was not supplied with one.

		my $mon = InCharge::SimpleMonitoring->get;
        my $pGroup = $mon->groupObjectByParameter( "hostname" => undef, 
                                                   "port"     => 25 );

        foreach $group ( $paramGroup->groups() ) {
            my $hostname = $group{parameters}{hostname};
            my $port     = $group{parameters}{port};

            # Common setup
            #
            my $sock = IO::Socket::INET->new(
                                   PeerAddr => $hostname,
                                   PeerPort => $port,
                                   Proto => 'tcp'
                                  );

            $sock->getline(); # Read and ignore banner


            #
            # Individual object processing
            #
            foreach $obj ( $group->objects() ) {
                my $command = $theObj->{parameters}{command};
                # Do command
                print $sock "$command\n";
                $line = $sock->getline();
                $hasError =  ( $line =~ /^25/ ? 0 : 1);
                #
                $attrError = $obj->instruments{IsErrorSymptom};
                if ( defined($attrError) ) {
                   $attrError->setvalue();
                }
            }

            # Common cleanup
            $sock->close();
        }

=cut

sub groupObjectByParameter {
  my $self = shift;
  my %args = @_;
  my $psGroup = InCharge::ParamGroupSet->new;
  $psGroup->groupByParameter($self,%args);
  return $psGroup;
}

=item B<setDebug>

=item B<setVerbose>

	Static methods to set debug or verbose flags, respectively.
	Both flags are useful primarily during the Monitoring object
	initialization hence these flags are best set before calling
	I<new> or I<get>. The debug flag is also applicable when exiting
	from the script,

	If active at initialization, the debug flag tells the module to
	print on standard error the complete list of global parameters,
	objects and attributes passed by the InCharge server to the
	script. If active when the script exits, the list of attributes
	and the values which have been set by the script are printed.

	The verbose flag forces the Monitoring object initialization
	routine to echo each line it reads from the InCharge server to
	standard error. Action and object parameters and the object
	attributes to be monitored are passed by the server in a
	line-oriented text format, so the verbose flag can be used as
	a sanity check.

	Among other things, an action script can redirect both outputs
	to a disk file by the following Perl incantation:

		my $handle = open(">> perldebug.txt");
		*STDERR = $handle;

	Usage:
		InCharge::Monitoring->setDebug;
		InCharge::Monitoring->setVerbose;

=cut

sub setDebug	{ $__debug = 1; }
sub setVerbose	{ $__verbose = 1; }


sub _logerr($$) {
	my ($level, $msg) = @_;
	$msg =~ s/[\r\n]/ /g;
	print STDOUT "$level $msg\n";
	}

=item B<logquiet>(message)

=item B<logdebug>(message)

=item B<lognotice>(message)

=item B<logwarning>(message)

=item B<logerror>(message)

	These methods insert the message string argument into the InCharge
	server log with the corresponding severity level codes, by which
	the messages can be filtered by a common level setting. Each
	message is automatically prefixed with a timestamp by the server.

	An action script can print messages to a different disk file using
	the usual Perl mechanisms. Printing to standard out is discouraged,
	however, because

	* the standard out is as such used to return attribute values to
	  the server and could overflow the return buffer, and 

	* the server will very likely parse out your messages so you will
	  never see them!

	You can, however, print to STDERR and redirect that to a file, as
	suggested above.

=cut

sub logquiet {
	my ($self, $msg) = @_;
	&_logerr("Quiet", $msg);
	}

sub logdebug {
	my ($self, $msg) = @_;
	&_logerr("Debug", $msg);
	}

sub lognotice {
	my ($self, $msg) = @_;
	&_logerr("Notice", $msg);
	}

sub logwarning {
	my ($self, $msg) = @_;
	&_logerr("Warning", $msg);
	}

sub logerror {
	my ($self, $msg) = @_;
	&_logerr("Error", $msg);
	}

=back

=cut

sub DESTROY { }

# }}}

# ---------------------------------------------------------------------
# debug only {{{

sub __printObjects {
	my ($self, $msg) = @_;
	my $Objects = $self->{objects};
	my $outstr = "--->>> ".$msg."\n";

	for my $id (keys %$Objects) {

		my $obj = $$Objects{$id};
		$outstr = $outstr.$obj->display."\n";
		}

	$outstr =  $outstr."<<<--- ".$msg."\n";
	$self->logdebug($outstr);
	}


sub __printAttributes {
	my ($self, $msg) = @_;
	my $Attributes = $self->{attributes};
	my $outstr = "--->>> ".$msg."\n";

	for my $id (keys %$Attributes) {

		my $attr = $$Attributes{$id};
		$outstr = $outstr.$attr->display."\n";

		}

	$outstr = $outstr."<<<--- ".$msg."\n";
	$self->logdebug($outstr);
	}

# }}}

# ---------------------------------------------------------------------
# Protocol {{{

sub __mkobj($$) {
	my ($className, $instName) = @_;

	my $obj = InCharge::MonitoredObject->new;
		$obj->{className}	= $className;
		$obj->{instName}	= $instName;
		$obj->{parameters}	= {};
		$obj->{attrlist}	= ();
		$obj->{instlist}	= ();
		$obj->{id}			= $className."::".$instName;

	return $obj;
	}

sub __dehex {
	my $str = shift;
	my $len = (length $str) / 2;
	my $out = "";

	for (my $i = 0; $i < $len; $i++) {
		$out = $out.chr hex substr $str, $i * 2, 2;
		}

	return $out;
	}

sub __read($) {

	my $self = shift;
	my $obj;
	my $attr;
	my $w = '[\_\/\w\.\[\]>-]';

	my %Parameters;
	my %Objects;
	my %Attributes;
	my %Instruments;

	my %ObjAttr;
	my %ObjInst;

	while (<STDIN>) {
		s/\r//;
		$self->logdebug($_) if $__verbose;
		last if /^EOF/;

		if (/Timeout\s+(.*)/) {

			if (defined $obj) {
				$obj->{timeout} = $1;
				}
			else {
				$SM_TIMEOUT = $1;
				}

			if ($1 =~ /^\d+(\.?\d*([+-]?[eE][+-]?\d+)?)?$/) {
				$self->logdebug("t ".$SM_TIMEOUT."\n")
					if $__debug && ! defined $obj;
				}
			else {
				die "Bad number format: $_";
				}

			next;
			}
		# if (/Object\s+($w+)::(.*)\s+(\d+(\.?\d*([+-]?[eE][+-]?\d+)?)?)?$/) {
		if (/Object\s+($w+)::(.*)/) {

			my $class = $1;
			my $inst = $2;

			if (defined $obj) { # for previous object
				$obj->{attributes}	= { %ObjAttr };
				$obj->{instruments}	= { %ObjInst };
				$Objects{$obj->{id}} = $obj;
				}

			$obj = &__mkobj($class, $inst);
			# $obj->{timeout} = $3 if defined $3;
			# $obj->{retries} = $4 if defined $4;

			$self->logdebug("o ".$obj->display."\n")
				if $__debug && defined $obj;

			undef %ObjAttr;
			undef %ObjInst;
			next;
			}
		#
		# instrument (mapping info) is still treated as optional
		# (this way, attribute parsing will not break if
		# integ-accessor backtracks to not reusing the attrib
		# name as the mapping info.)
		#
		#                1:cls  2:ins  3:att   4:typ   5:instr
		# if (/Attribute\s+($w+)::(.*)::($w+)\s+(\d+)\s*($w+)?$/) {

		#                1:att   2:typ   3:instr
		if (/Attribute\s+($w+)\s+(\d+)\s*($w+)?$/) {

			my $info;
			$info = $3 if $3;

			die "Protocol error: missing object declaration for "
					."attribute ".$1
				unless defined $obj;

			$attr = InCharge::Attribute->new;
				$attr->{id}			= $obj->{id}."::".$1;
				$attr->{object}		= $obj;
				$attr->{attribute} 	= $1;
				$attr->{_type} 		= $2;
				$attr->{instrument}	= $info;
				$attr->{error}		= "";

			$Attributes{$attr->{id}} = $attr;
			$ObjAttr{$1} = $attr;
			push @{$obj->{attrlist}}, $attr->{id};

			if ($info) {
				$ObjInst{$info} = $attr;
				push @{$obj->{instlist}}, $info;
				my $infoid = $obj->{id}."::".$info;
				$Instruments{$infoid} = $attr;
				}

			$self->logdebug("> ".$attr->display()."\n") if $__debug;
			next;
			}
		#
		if (/Var\s+($w+)=\'(.*)\'/) {
			my $key = $1;
			my $value = &__dehex($2);
			if (defined $obj) {
				${$obj->{parameters}}{$key} = $value;
				$self->logdebug(":: $key = $value\n") if $__debug;
				}
			else {
				$Parameters{$key} = $value;
				$self->logdebug(": $key = $value\n") if $__debug;
				}
			next;
			}
		}

	if (defined $obj) { # for this last object
		$obj->{attributes}	= { %ObjAttr };
		$obj->{instruments}	= { %ObjInst };
		$Objects{$obj->{id}} = $obj;
		}

	$__monitoring->{parameters}	 = \%Parameters;
	$__monitoring->{objects} 	 = \%Objects;
	$__monitoring->{attributes}	 = \%Attributes;
	$__monitoring->{instruments} = \%Instruments;
	$__monitoring->{timeout}	 = \$SM_TIMEOUT;
	}


sub __write {
	my $Objects	= $__monitoring->{objects};

	for my $id (keys %$Objects) {
		my $obj = $$Objects{$id};
		my $attrs = $obj->{attributes};

		print STDOUT "Object ".$id
					."\n";

		for my $attrid (keys %$attrs) {
			my $attr = $$attrs{$attrid};

			print STDOUT "Attribute ".$attr->{attribute}
					." ".$attr->{error}
					."\n";

			if (defined $attr->{value}) {
				print STDOUT "Value ".$attr->{_type}." ";

				#print STDOUT length($attr->{value})." "
				#	if $attr->typename eq "ATTR_STRING";

				if ($attr->typename eq "ATTR_CHAR" && length $attr->{value} == 1) {
					# quietly quote the lone character
					print STDOUT "'$attr->{value}'\n";
					}
				else {
					print STDOUT $attr->{value}."\n";
					}
				}

			print STDOUT "\n";		# paranoid separator
			}
		}

	print STDOUT "EOF\n";		# terminator
	}


sub __init {
	my $self = shift;

	&__read($self);
	&__printObjects($self, "Input objects") if $__debug;
	&__printAttributes($self, "Input attributes") if $__debug;

	$SM_PARAMETER	= $self->{parameters};
	$SM_OBJECT		= $self->{objects};
	$SM_ATTRIBUTE	= $self->{attributes};
	$SM_INSTRUMENT	= $self->{instruments};
	}


sub __fini {
	my $self = shift;

	&__printAttributes($self, "Output attributes") if $__debug;
	&__write;
	}

#END { &__fini($__monitoring) if $__monitoring; }

END {
        exit($? >> 8) if ($? >> 8);
        if ($@) {
                &logerror($@);
                exit(-1);
                }
 
        &__fini($__monitoring) if $__monitoring;
    }



# }}}

1;
__END__
# Documentation {{{

=pod 

=head1 FILES
	
	Action scripts will be executed only if located in
		$SM_SITEMOD/local/integration/
		$SM_SITEMOD/integration/
		$SM_HOME/local/integration/
		$SM_HOME/integration/
	in that order.


=head1 SEE ALSO

	L<InCharge::Attribute>,
	L<InCharge::MonitoredObject>

=cut
# }}}
#### eof ####	vi:set ts=4 sw=4: vim:set fdm=marker:
