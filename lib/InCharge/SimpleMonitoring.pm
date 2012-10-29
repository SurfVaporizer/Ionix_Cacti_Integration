# ---------------------------------------------------------------------
#
# InCharge support for monitoring using Perl
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
# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-accessor/perl/SimpleMonitoring.pm#1 $
#
# ---------------------------------------------------------------------
# Packet interface and settings {{{

package InCharge::SimpleMonitoring;

=head1 NAME

	InCharge::SimpleMonitoring -
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

our $VERSION = '1.1';

use Carp qw(croak carp);
use Exporter;

use InCharge::Monitoring 
  qw($SM_PARAMETER $SM_OBJECT $SM_ATTRIBUTE
     $SM_INSTRUMENT $SM_TIMEOUT setDebug setVerbose); 
use InCharge::ParamGroupSet; use InCharge::ParamGroup;

use vars qw( 
		@ISA 
		@EXPORT
		@EXPORT_OK 
		$SM_ATTRIBUTE
		$SM_INSTRUMENT
		$SM_PARAMETER
		$SM_OBJECT
	   );
	   
@ISA = ('Exporter');

@EXPORT = qw(
		$SM_PARAMETER
		$SM_OBJECT
		$SM_ATTRIBUTE
		$SM_INSTRUMENT
		$SM_TIMEOUT);

@EXPORT_OK = qw(
		get
		setDebug
		setVerbose
	);

=head1 SYNOPSIS


	use InCharge::SimpleMonitoring;

	InCharge::SimpleMonitoring->setDebug;
	InCharge::SimpleMonitoring->setVerbose;

	my $monitor = InCharge::SimpleMonitoring->new;
	 -- OR --
	my $monitor = InCharge::SimpleMonitoring->get;



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
	my $attr  = $$SM_INSTRUMENT{$class."::".$inst."::".$attrib);
	my $attr  = $$SM_ATTRIBUTE{$class."::".$inst."::".$attrib);
	my $attr  = $$SM_OBJECT{$class."::".$inst);

	my $param_hash	= $monitor->{parameters};
	my $object_hash	= $monitor->{objects};
	my $attrib_hash	= $monitor->{attributes};

	... etc ...


=head1 DESCRIPTION

	The InCharge::SimpleMonitoring module enables monitoring of a
	single object in the InCharge server repository using a Perl script.
	This module file is part of the InCharge::Monitoring package
	and is installed in the same directory (along with perlApi).

	This module provides minor simplfication for action scripts
	intended for updating the attributes of exactly one model object
	per invocation.

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

my $__simple;
my $__fullmon;

my $fields = {
	parameters	=> undef,
	attributes	=> undef,
	instruments	=> undef,
	};


=head2 Methods

=over 4

=item B<new>

	Static constructor to create and initialize a SimpleMonitoring
	object. There can be only one Monitoring object (since a given
	action process would have exactly one InCharge server that
	invoked it). Method invocation:

		my $mon = InCharge::SimpleMonitoring->new;

	Will L<croak> if called more than once in an action process.
	Internally calls InCharge::Monitoring->new and massages the
	resulting data structures.

=cut

sub new {
	croak "Only one SimpleMonitoring instance allowed" if $__simple;

	my $__fullmon = InCharge::Monitoring->new;
	my $Objects = $__fullmon->{objects};

	croak "Invocation error: NO objects to monitor"
		unless defined $Objects;

	my @objids = keys %$Objects;

	croak "Invocation error: NO objects to monitor"
		if $#objids < 0;

	croak "Multiple monitored objects -- use InCharge::Monitoring"
		if $#objids > 0;

	my $that = shift;
	my $class = ref($that) || $that;
	my $self = { %$fields };
	bless $self, $class;

	$SM_PARAMETER	= $self->{parameters} = $__fullmon->{parameters};
	$SM_ATTRIBUTE	= {};
	$SM_INSTRUMENT	= {};

	my $obj = $Objects->{$objids[0]};

	my $w = '[\/\w\.>-]';
	$SM_OBJECT = $obj;

	my $objparams = $obj->{parameters};
	for my $name (keys %$objparams) {
		my $value = $$objparams{$name};
		$$SM_PARAMETER{$name} = $value;
		}

	my $attrs = $__fullmon->{attributes};
	for my $key (keys %$attrs) {
		my $attr = $$attrs{$key};
		my $name = $attr->{attribute};
		$$SM_ATTRIBUTE{$name} = $attr;
		if ($name =~ /($w+)::($w+)::($w+)/) {
			# ensure instrumentation name key
			$$SM_ATTRIBUTE{$3} = $attr;
			}
		else {
			# ensure full name key
			$$SM_ATTRIBUTE{$obj->{id}."::".$name} = $attr;
			}
		}
	$self->{attributes} = \%$SM_ATTRIBUTE;

	my $instrs = $__fullmon->{instruments};
	for my $key (keys %$instrs) {
		my $attr = $$instrs{$key};
		my $name = $attr->{instrument};
		$$SM_INSTRUMENT{$name} = $attr;
		if ($name =~ /($w+)::($w+)::($w+)/) {
			# ensure instrumentation name key
			$$SM_INSTRUMENT{$3} = $attr;
			}
		else {
			# ensure full name key
			$$SM_INSTRUMENT{$obj->{id}."::".$name} = $attr;
			}
		}
	$self->{instruments} = \%$SM_INSTRUMENT;

	$SM_TIMEOUT = $__fullmon->{timeout};
    
    $self->{objects} = $__fullmon->{objects};

	$__simple = $self;
	return $self;
	};

=item B<get>

	Static constructor method to retrieve reference to existing
	SimpleMonitoring interface object. If it doesn't exist, the new
	method is silently called.  Invoked as

		my $mon = InCharge::SimpleMonitoring->get;

=cut

sub get {
	&new unless $__simple;
	return $__simple;
	}

sub DESTROY { }


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
		InCharge::SimpleMonitoring->setDebug;
		InCharge::SimpleMonitoring->setVerbose;

	(These methods are simply inherited from InCharge::Monitoring.)

=back

=cut


# }}}

# ---------------------------------------------------------------------
1;
__END__
# Documentation {{{

=head2 Data members

=over 4

=item B<{parameters}>

=item B<%$SM_PARAMETER>

	Hash table of key-value parameter strings set up in the (model)
	action object.

	These parameters are common to all invocations of that action,
	regardless of which object is being polled.  Accessible through
	the monitoring interface object as

		$mon->{parameters}

	or directly as a global variable (polluting your namespace!)

		%$SM_PARAMETER


=item B<$SM_OBJECT>

	Reference to the L<MonitoredObject> data structure representing
	model object being polled. It contains the following members:

	* A list of object-specific parameters (defined in the
	  L<Runtime_Parameters> associated with the object).

	* The list of attributes belonging to that object that need to be
	  monitored, designated "instrumented" in L<MODEL> (for historical
	  reasons having to do with SNMP).

	* A list of "instruments", that is model-independent name strings,
	  corresponding to the attributes (see L<SM_INSTRUMENT> below).


=item B<{attributes}>

=item B<%$SM_ATTRIBUTE>

=item B<{instruments}>

=item B<%$SM_INSTRUMENT>

	Hash table of all attributes requested for update by the server.
	That is, the full list of attributes of the object identified
	in $SM_OBJECT.

	Keys are strings of the form "$class::$instance::$attribute"
	in %$SM_ATTRIBUTE, where $attribute is the attribute name as
	defined in the model. Model-independent keys are provided in
	%$SM_INSTRUMENT in the form "$class::$instance::$instrument".

	For convenience, the attribute or instrument name strings can
	be themselves directly used as keys into this table, since
	the class and object instance names would be common for all
	of the attributes.

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

	An action script that wants to budget the time it spends between
	general initialization and object-specific activity can look up
	the timeout value given in the corresponding L<MonitoredObject>
	data structure referenced by $SM_OBJECT.

=back

=head1 FILES
	
	Attribute.pm MonitoredObject.pm Monitoring.pm


=head1 SEE ALSO

	L<InCharge::Attribute>,
	L<InCharge::MonitoredObject>,
	L<InCharge::Monitoring>

=cut
# }}}
#### eof ####	vi:set ts=4 sw=4: vim:set fdm=marker:
