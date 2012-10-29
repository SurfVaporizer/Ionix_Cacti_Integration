# ---------------------------------------------------------------------
#
# InCharge support for monitoring using Perl: Monitored Object
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
# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-accessor/perl/MonitoredObject.pm#1 $
#
# ---------------------------------------------------------------------
# Packet interface and settings {{{

package InCharge::MonitoredObject;

=head1 NAME

	InCharge::MonitoredObject -
	MonitoredObject data structure in Perl-based monitoring
	for SMARTS InCharge servers.

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

use Data::Dumper;

use vars qw( 
		@ISA 
		@EXPORT
		@EXPORT_OK 
	   );
	   
@ISA = ('Exporter');

@EXPORT = qw();

=head1 SYNOPSIS

	use InCharge::Monitoring;


=head1 DESCRIPTION

	This module is included by L<InCharge::Monitoring> and defines
	the monitored model object data structure.

	This module should never be included directly by action scripts.
	Monitored objects should never be constructed directly by the
	action scripts.

=cut

# }}}

# ---------------------------------------------------------------------
# class members {{{

my $fields = {
	id		=> undef,
	className	=> undef,
	instName	=> undef,
	attrlist	=> undef,
	instlist	=> undef,
	parameters	=> undef,
	attributes	=> undef,
	timeout		=> undef,
	#retries	=> undef,
	};

sub new {
	my $that = shift;
	my $class = ref($that) || $that;
	my $self = { %$fields };
	bless $self, $class;
	return $self;
	}

sub DESTROY { }


=head2 Data members

=over 4

=item B<{id}>

	A string id of the form "$class::$instance", where $class is the
	model class and $instance is the instance name of the monitored
	model object, which is typically created by a discovery probe
	or adapter.

	Parsing the id is discouraged -- and unnecessary: see below.

=item B<{className}>

	Model class name string.

=item B<instName>

	Model object name this data structure corresponds to. I.e. the
	object that is being polled.

=item B<{attrlist}>

	List of space-separated attribute names belonging to this object.
	Only the "instrumented" attributes, which are polled, are listed.
	(The class and object instance names are not repeated in the
	attribute names.)


=item B<{instlist}>

	List of space-separated instrument names corresponding to the
	attribute names listed in I<attrlist>.

=item B<{parameters}>

	Hash table of object-specific key-value strings, set by the
	discovery probe or adapter using a L<Runtime_Parameters> object
	when connecting the model object instance to the Integration
	Accessor. Example usage:

		my $dump = open (">> /tmp/perldump.txt");
		*STDERR = $dump;

		foreach my $obj (values %$SM_OBJECT) {
			print STDERR "$obj->{id}:\n";
			while (my ($objkey $objvalue) = each %$obj->{parameters}) {
				print STDERR "\t".$objkey." --> ".$objvalue."\n";
			}
		}

=back

=head2 Methods

=over 4

=item B<display>

	Returns a printable string representation of the monitored
	object structure, as a debugging aid.

	(Equivalent to the I<toString> method in Java.)

=back

=cut

sub display {
	my $self = shift;
	my $attrs = $self->{attrlist};
	my $insts = $self->{instlist};

	my $ret = $self->{id};

	$ret = $ret." attributes(@$attrs)"
		if defined $attrs;

	$ret = $ret." instruments(@$insts)"
		if defined $insts;

	$ret = $ret." parameters(";
	my $params = $self->{parameters};
	while (my ($key, $value) = each %$params) {
		$ret = $ret."$key => $value, ";
		}
	$ret = $ret.")";

	$ret = $ret." timeout($self->{timeout})"
		if defined $self->{timeout};

	#$ret = $ret." retries($self->{retries})"
	#	if defined $self->{retries};

	return $ret.")";
	}

# }}}
# ---------------------------------------------------------------------
1;
__END__

=pod

=head1 SEE ALSO

	L<InCharge::Monitoring>,
	L<InCharge::Attribute>

=cut
#### eof ####	vi:set ts=4 sw=4: vim:set fdm=marker:
