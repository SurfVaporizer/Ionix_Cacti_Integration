# ---------------------------------------------------------------------
#
# InCharge support for monitoring using Perl: Attribute structure
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
# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-accessor/perl/Attribute.pm#1 $
#
# ---------------------------------------------------------------------
# Packet interface and settings {{{

package InCharge::Attribute;

=head1 NAME

	InCharge::Attribute -
	Attribute data structure in Perl-based monitoring
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

@EXPORT = qw(
		typename
		setvalue
		seterror
	);


=head1 SYNOPSIS

	use InCharge::Monitoring;


=head1 DESCRIPTION

	This module is included by L<InCharge::Monitoring> and defines
	the attribute data structure.

	This module should never be included directly by action scripts.
	Attribute data objects should never be constructed directly by
	the action scripts.

=cut

# }}}

# ---------------------------------------------------------------------
# class members {{{ 

my $fields = {	# almost as in <integ-accessor/ma_attr.h>
	id			=> undef,
	object		=> undef,	# monitored
	attribute	=> undef,
	instrument	=> undef,
	_type		=> undef,
	error		=> undef,
	value		=> undef,
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

	A string id of the form "$class::$instance::$attribute", where
	$class and $attribute are the model class and model specified
	attribute names, and $instance is the model object name created
	typically by a discovery probe or adapter.

	Parsing the id is discouraged.

=item B<{object}>

	Reference to the L<MonitoredObject> structure bearing the
	object-specific parameters, etc.

=item B<attribute>

	Model-defined attribute name string.

=item B<{instrument}>

	Model-independent identifier for this attribute. Instrument
	strings must be specified in the model in order to be passed
	to the action, but would be coordinated independently of the
	model code.

=item B<{value}>

	Return value if any has been set by the action.

	Do not set this directly -- use the setvalue($) method.

=item B<{error}>

	Error message if any has been set by the action.

	Do not set this directly -- use one of the set methods below.

=back

=head2 Methods

=over 4

=item B<setvalue($)>

	Sets the return value of this attribute to the argument.
	The value will be returned to the server as a text string.
	Any error message previously set is silently cleared.
	See also the L<typename> method below.

=cut

sub setvalue {
	my ($self, $value) = @_;
	$self->{value} = $value;
	$self->{error} = "" if $self->{error} =~ /Error/;
	}

=item B<setoldvalue()>

	Sets the return value of this attribute to its current value.
	Only an internal flag is set -- the actual current value is
	never accessible to the action,

=cut

sub setoldvalue {
	my $self = shift;
	$self->{error} = "Keepold";
	undef $self->{value};
	}

sub _seterr {
	my ($self, $level, $msg) = @_;
	$msg =~ s/[\r\n]/ /g;
	$self->{error} = "$level $msg";
	}

=item B<setquiet($)>

	Sets a log message on the attribute to be notified to the 
	server, with a severity level of QUIET.  A return value, if
	set, will also be returned to the server.

=cut

sub setquiet {
	my ($self, $error) = @_;
	$self->_seterr("Quiet", $error);
	}

=item B<setdebug($)>

	Sets a log message on the attribute to be notified to the 
	server, with a severity level of DEBUG.  A return value, if
	set, will also be returned to the server.

=cut

sub setdebug {
	my ($self, $error) = @_;
	$self->_seterr("Debug", $error);
	}

=item B<setnotice($)>

	Sets a log message on the attribute to be notified to the 
	server, with a severity level of NOTICE.  A return value, if
	set, will also be returned to the server.

=cut

sub setnotice {
	my ($self, $error) = @_;
	$self->_seterr("Notice", $error);
	}

=item B<setwarning($)>

	Sets a log message on the attribute to be notified to the 
	server, with a severity level of WARNING.  A return value, if
	set, will also be returned to the server.

=cut

sub setwarning {
	my ($self, $error) = @_;
	$self->_seterr("Warning", $error);
	}

=item B<seterror($)>

	Sets a log message on the attribute to be notified to the 
	server, with a severity level of ERROR.  A return value, if
	already set, will be cleared and NOT returned to the server.

=cut

sub seterror {
	my ($self, $error) = @_;
	$self->_seterr("Error", $error);
	undef $self->{value};
	}

=item B<typename>

	Returns a string identifying the type of value expected at
	the server, one of:

		"ATTR_UNDEFINED",
		"ATTR_BOOLEAN",
		"ATTR_SHORT",
		"ATTR_INT",
		"ATTR_LONG",
		"ATTR_UNSIGNED_SHORT",
		"ATTR_UNSIGNED_INT",
		"ATTR_UNSIGNED_LONG",
		"ATTR_FLOAT",
		"ATTR_DOUBLE",
		"ATTR_STRING",
		"ATTR_CHAR"

	Note that LONG and UNSIGNED LONG are defined to be of 64 bits
	in InCharge models.

=cut

sub typename {
	my $self = shift;
	return (
		"ATTR_UNDEFINED",
		"ATTR_BOOLEAN",
		"ATTR_SHORT",
		"ATTR_INT",
		"ATTR_LONG",
		"ATTR_UNSIGNED_SHORT",
		"ATTR_UNSIGNED_INT",
		"ATTR_UNSIGNED_LONG",
		"ATTR_FLOAT",
		"ATTR_DOUBLE",
		"ATTR_STRING",
		"ATTR_CHAR"
	)[$self->{_type}];
	}

=item B<display>

	Returns a printable string representation of the attribute
	structure, as a debugging aid.

	(Equivalent to the I<toString> method in Java.)

=cut

sub display {
	my $self = shift;
	my $mobj = $self->{object};

	return
		$mobj->{id}
		."::".$self->{attribute}
		." instrument=(".$self->{instrument}
		.") type=".$self->typename
		."(".$self->{_type}.") value("
		.(defined $self->{value}
			? $self->{value} : "undef")
		.") error(".$self->{error}
		.")"
		;
	}

=back

=cut

# }}}

# ---------------------------------------------------------------------
1;
__END__

=pod

=head1 SEE ALSO

	L<InCharge::Monitoring>,
	L<InCharge::MonitoredObject>

=cut
#### eof ####	vi:set ts=4 sw=4: vim:set fdm=marker:
