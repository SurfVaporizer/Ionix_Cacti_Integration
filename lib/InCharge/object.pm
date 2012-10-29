#+ object.pm - access to SMARTS InCharge repository objects
#
# Copyright (c) 2003 System Management ARTS (SMARTS)
# All Rights Reserved.
#
# SMARTS provides this program 'as is' for educational and illustrative
# purposes only, without warranty or support.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/perlApi/perl/object.pm#1 $
# $Source: /src/MASTER/smarts/perlApi/perl/object.pm,v $
#
#PDF_TITLE=RPA Object manipulation


package InCharge::object;

=head1 NAME

InCharge::object - Access to SMARTS InCharge repository objects.

=head1 COPYRIGHT

 Copyright (c) 2003 System Management ARTS (SMARTS)
 All Rights Reserved.

=head1 SYNOPSIS

  use InCharge::session;

  $obj = $session->object( $class, $instance );

  $value = $obj->get( "PropertyName" );
  $value = $obj->{PropertyName};

  $obj->put( "PropertyName", $value );
  $obj->{PropertyName} = $value;

  $rtn = $obj->invoke( "OperationName", .. arguments .. );
  $rtn = $obj->OperationName( .. arguments .. );

    ... etc ...

=head1 DESCRIPTION

The InCharge::object module allows objects in the InCharge repository to be
manipulated in an "OO" style, similar to the ASL language.

In order to access the methods (operations) and fields (properties) of an
repository object, you first create an InCharge::object to refer to it. This is
done using the "object" or "create" operations of the InCharge::session module
(see L<InCharge::session>). The "object" method simply sets up the perl data
structures required, without referring to the remote server. The "create"
method creates the object in the remote repository, and returns an
InCharge::object referring to it. For example..

    $obj = $session->object( "Router", "edgert1" );
    $obj = $session->object( "Router::edgert1" );
    $obj = $session->create( "Router", "newrouter" );

Note that whenever you specify the details of a repository instance to work
with in RPA, you have a choice of two syntaxes.  You can either specify the
object class and instance names as individual arguments, or you can run them
together with a delimiting "::". RPA handles these two syntax identically.

If you don't know the class to which an object belongs, you can either use a
class argument of "undef", or a string with nothing before the "::". For
example..

    $obj = $session->object( undef, "edgert1" );
    $obj = $session->object( "::edgert1" );

The option of omitting the class name does NOT work with the
"InCharge::session-E<gt>create" method because InCharge cant create an object
without knowing which class to use. It does work with
"InCharge::session-E<gt>object" and related calls because the process of
referring to an existing instance can legitimately include a query to identify
the object's class. You should note that RPA needs to do some additional work
to determine the object's class, and so there wll be a slight performance hit
if you choose not to provide the class name in these calls.

Once an object reference has been create, it can be used to invoke the object's
operations, or access it's properties. Access to an object's fields can be
obtained using calls like the following..

    $vendor = $obj->get( "Vendor" );
    $vendor = $obj->{Vendor};
    ($vendor,$model) = $obj->get( "Vendor", "Model" );
    %properties = $obj->get( );

    $obj->put( "Vendor", "Cisco" );
    $obj->{Vendor} = "Cisco";
    $obj->put(
	Vendor => "Cisco",
	Model => "2010"
    );

These examples show that object properties can be accessed using either the
"get" and "put" methods, or via the psuedo-hash syntax. The latter syntax is
preferred because it is closer to the original InCharge built in ASL language
logic.

Two special "internal" properties can be accessed using the hash syntax only,
these give the name of the class and instance to which the object reference
refers. Treat them as read-only fields.

    $obj->{_class}	     BUT NOT: $obj->get("_class")
    $obj->{_instance}	     BUT NOT: $obj->get("_instance")

Object operations can be invoked using the "invoke" method, or directly,
like this..

    @ports = $obj->invoke( "findPorts" );
    @ports = $obj->findPorts();

    $port = $obj->invoke( "makePort", "1.0", "PORT-rt1/1.0", "Port" );
    $port = $obj->makePort( "1.0", "PORT-rt1/1.0", "Port" );

Again: the latter syntax (calling the operation directly) is preferred.

You need to resort to the "invoke" method if you want to access an object
operation that duplicates the name of any of the build-in methods of the
InCharge::object class. The first of these two calls the "new" operation of the
object in the repository, whereas the second calls the build-in "new" method of
the InCharge::object class.

    $obj->invoke( "new", "qtable" );
    $obj->new( "qtable" );

Note that InCharge::object is used for accessing ICIM instance "operations" and
"properties" only, if you wish to make other ICIM calls that refer to instances
(such as "subscribe"), then you should use the features of InCharge::session
directly. So, you cannot say..

    $obj->propertySubscribe( "Vendor" );

instead, you must use..

    $session->propertySubscribe( $class, $instance, "Vendor" );

or
    $session->propertySubscribe( $obj, "Vendor" );

This is because the "propertySubscribe" is not a repository class operation,
but a "primitive". It you wish to see what operations are available for a
particular class, via the InCharge::object module, use the RPA Dashboard
application, or the "dmctl" command as follows..

    dmctl -s DOMAIN getOperations CLASSNAME | more

Likewise, to determine what properties can be accessed using this module use
the Dashboard, or try..

    dmctl -s DOMAIN getProperties CLASSNAME | more

=head1 FUNCTIONS AND METHODS

=over 4

=cut

use 5.006;
# use strict;
use warnings;
use Data::Dumper;
our $VERSION = '2.01';


sub throw {
    &InCharge::session::throw( @_ );
}

#--------------------------------------------------------------------------

=item B<object>

 $object = $session->object( $class, $instance );

creates a new object reference. See L<InCharge::session>
for fuller details.

=cut

#--------------------------------------------------------------------------

# the InCharge::object::new subroutine is used internally by
# InCharge::session::object when a new object reference is being created.
# Don't call this function directly from within a user script

sub new {
    my ( $pkg, $session, @in ) = @_;

    throw "[10] Not attached to an InCharge domain manager"
	if ($session->broken());

    throw "[1] Missing session argument for ${pkg}::new"
	unless (defined $session);

    if ( $#in == 0 && $in[0] !~ m/::/ ) {
	unshift @in, undef;
    }

    # the specified object name can be any of the allowed syntaxes
    # that are documented in session.pdf.

    my ( $class, $instance ) = $session->_getObject( \@in, 0 );

    throw "[1] Too many arguments for ${pkg}::new"
	if (@in);

    # populate a HASH with the information required to allow an InCharge
    # object to be a perl object, then tie and bless it.

    my %self;

    tie %self, $pkg, {
	_session => $session,
	_class => $class,
	_instance => $instance
    };

    #return bless \%self, $pkg;	    # REQUIRED for subclassing InCharge::object
    return bless \%self;	    
}

#--------------------------------------------------------------------------

=item B<get>

 $result = $obj->get( $property_name [, $property_name ...] )

Or ...

 $result = $obj->{$property_name};

Or ...

 %all_properties = $obj->get( )

Gets the value for the specified property(s) of the object.

The type of return value depends on the calling syntax used ("get" or hash) and
the perl evaluation context (scalar or array) as per the following table.

					     return type in..
 Expression syntax   property type   scalar context   array context
 -----------------   -------------   --------------   -------------
 $obj->{prop}	       scalar	      scalar	       scalar in [0]
 $obj->{prop}	       array	      array ref        array ref in [0]
 $obj->get("prop")     scalar	      scalar	       scalar in [0]
 $obj->get("prop")     array	      array ref        array

Multiple values are always returned in an array (or array reference).

If you wish to access the content of a property who's name is held in a
variable, you can naturally use the perl "typical" logic, like this..

 $propname = "Vendor";
 $value = $obj->{$propname};

You can also get multiple values in a single "get()" call by listing all the
property names as arguments.  The results are returned in an array. On an
InCharge server version 6 or later, this is quicker than using multiple
single-property "get()s". On Servers before version 6; there is no difference.

 ( $vendor, $type ) = $obj->get( "Vendor", "Type" );

You can also call "get()" with no arguments, in which case it creates a hash
containing all the object properties and relations. There is no syntactical
advantage this this, but there is a significant speed advantage on InCharge
server version 6 and later.

See also the "get_t" call which extends the functionality of this one by
returning additional information, to identify the type of data held in the
property.

Note that "get" and "get_t" throw an error when used to access a non-existant
property, or one that cannot be retrieved for any reason, where as the
psuedo-hash syntax symply returns an "undef" value. This difference allows the
Data::Dumper logic to display an entire object without erroring even when some
properties cant be retrieved.

=cut

#--------------------------------------------------------------------------

sub get {
    my ( $obj, @props ) = @_;
    my $s = $obj->{_session};

    # Don't care for now how many. Just check. Might be a bottleneck. 
    foreach my $prop ( @props ) {

	throw "[1] Invalid format for property requested \"::\" is not allowed"
		if ( $prop =~ m/::/ ); 

	throw "[1] Property name requested is not a scalar string"
		if ( ref($prop) eq "ARRAY" ); 
	    #Possibly add more checks
    }

    if (@props == 1) {
	return $s->get($obj, $props[0]);
    } elsif ( @props == 0  and 
			    $s->primitiveIsAvailable( "getAllProperties" )) {
	my @values = $s->getAllProperties($obj, 2);
	return wantarray ? @values : \@values;
    } elsif (@props == 0) {
	my @props = $s->getPropNames($obj->{_class});
	my %values = ( );
	foreach my $prop ( @props ) {
	    my $val = $s->get($obj, $prop);
	    $values{$prop} = $val;
	}
	return wantarray ? %values : \%values;
    } elsif ( $s->primitiveIsAvailable( "getMultipleProperties" ) ) {

	my @values = $s->getMultipleProperties($obj, [@props]);
	return wantarray ? @values : \@values;
    } else {
	my @values = ();
	foreach my $prop ( @props ) {
	    my $val = $s->get($obj, $prop);
	    push @values, $val;
	}
	return wantarray ? @values : \@values;
    }
}

#--------------------------------------------------------------------------

=item B<get_t>

 ($type, $value) = $obj->get_t( $property_name );

or ...

 @types_and_values = $obj->get_t( $prop1 [, $prop2 [, prop3 .. ] ] )

or ...

 %all_property_types_and_values = $obj->get_t( );

This is like the "get" method, except that it returns the type of the return
value as well as the value itself. The data types are encoded as integer
numbers, listed and explained in L<InCharge::remote>. If the return is an
array, then the "$value" will receive a reference to the array. If the return
is a scalar, then "$value" will hold it. The $type is always an integer number,
which can be converted to a more mnemonic string using $session->TYPE.

The 2nd syntax gets the types and values for multiple properties. Each
type/value pair is held in a 2-element sub-array within the returned data.

The 3rd syntax gets the types and values for all the properties and relations
of the object, and stores them in a hash, indexed by the property names. This
approach has a significant performance benefit when working with InCharge
server versions 6 and above.

Here's an example..

 $obj = $session->object( "Router::gw1" );
 ( $type, $value ) = $obj->get_t( "Vendor" );
 print "Vendor value='$value', type = ".$session->TYPE($type)."\n";

This example will print something like..

 Vendor value='CISCO', type = STRING

=cut

#--------------------------------------------------------------------------

sub get_t { # get a property, and type too
    my ( $obj, @props ) = @_;
    my $s = $obj->{_session};

    # Don't care for now how many. Just check. Might be a bottleneck. 
    foreach my $prop ( @props ) {

	throw "[1] Invalid format for property requested \"::\" is not allowed"
		if ( $prop =~ m/::/ ); 

	    #Possibly add more checks in the future
    }



    if (@props == 1) {
	return $s->get_t($obj, @props);
    } elsif ( @props == 0  and 
			$s->primitiveIsAvailable( "getAllProperties_t" ) ) {
	my @values = $s->getAllProperties_t($obj, 2);
	return wantarray ? @values : \@values;
    } elsif (@props == 0) {
	my @props = $s->getPropNames($obj->{_class});
	my %values = ( );
	foreach my $prop ( @props ) {
	    my $val = $s->get_t($obj, $prop);
	    $values{$prop} = $val;
	}
	return wantarray ? %values : \%values;
    } elsif ( $s->primitiveIsAvailable( "getMultipleProperties_t" ) ) {
	my @values = $s->getMultipleProperties_t($obj, [ @props ]);
	return wantarray ? @values : \@values;
    } else {
	my @values = ();
	foreach my $prop ( @props ) {
	    my $val = $s->get_t($obj, $prop);
	    push @values, $val;
	}
	return wantarray ? @values : \@values;
    }
}

sub get_T { # get a property, and type too
    my ( $obj, @props ) = @_;
    my $s = $obj->{_session};

    # Don't care for now how many. Just check. Might be a bottleneck. 
    foreach my $prop ( @props ) {

	throw "[1] Invalid format for property requested \"::\" is not allowed"
		if ( $prop =~ m/::/ ); 

	    #Possibly add more checks in the future
    }



    if (@props == 1) {
	return $s->get_T($obj, @props);
    } elsif ( @props == 0  and 
			$s->primitiveIsAvailable( "getAllProperties_t" ) ) {
	my @values = $s->getAllProperties_T($obj, 2);
	return wantarray ? @values : \@values;
    } elsif (@props == 0) {
	my @props = $s->getPropNames($obj->{_class});
	my %values = ( );
	foreach my $prop ( @props ) {
	    my $val = $s->get_T($obj, $prop);
	    $values{$prop} = $val;
	}
	return wantarray ? %values : \%values;
    } elsif ( $s->primitiveIsAvailable( "getMultipleProperties_t" ) ) {
	my @values = $s->getMultipleProperties_T($obj, [ @props ]);
	return wantarray ? @values : \@values;
    } else {
	my @values = ();
	foreach my $prop ( @props ) {
	    my $val = $s->get_T($obj, $prop);
	    push @values, $val;
	}
	return wantarray ? @values : \@values;
    }
}

#--------------------------------------------------------------------------

=item B<getRelation>

 $newref = $object->getRelation( $relation_name );

 @co = $object->getRelation( "ComposedOf" );

This method collects the value of a specified object relationship, and casts
it to an object reference. This is equivalent to using "get" to collect the
value, and then session->object(..) to obtain it's reference.

Works for both single and multiple relationships.

=cut

sub getRelation ($$) {
    throw "[1] Too many arguments for getRelation" if (@_ > 2);
    throw "[1] Too few arguments for getRelation"  if (@_ < 2);

    my ( $obj, $prop ) = @_;

    my $s = $obj->{_session};
    my ( $t, $v ) = $s->get_t( $obj, $prop );
    if ( $t == 14 ) {
	return $s->object( $v );
    } elsif ( $t == 28 ) {
	foreach ( @{$v} ) { $_ = $s->object( $_ ); }
	return wantarray ? @{$v} : $v;
    } else {
	throw "[1] Property '$prop' of class '$obj->{_class}' is not an object reference or object reference set.";
    }
}

#--------------------------------------------------------------------------

=item B<put>

 $object->put( $property_name, $value );

This method allows fields of the object to be modified in the InCharge
repository.

You can use this in a number of styles. The use of the pseudo-hash syntax is
the preferred option for syntactic equivalence to InCharge's native ASL
language.

 $obj->put( "Vendor", "Cisco" );
 $obj->{Vendor} = "Cisco";
 $obj->{ComposedOf} = [ ];

To set more than one property in a single call, you can use multiple
"name => value" pairs, like this..

 $obj->put(
    Vendor => "Cisco",
    PrimaryOwnerContact => "Joe Bloggs"
 );

or

 %updates = (
    Vendor => "Cisco",
    PrimaryOwnerContact => "Joe Bloggs"
 );
 $obj->put( %updates );

When using either syntax to set a relationship or list property, you should use
a reference to a perl array. Like this..

 $obj->{ComposedOf} = [ $a, $b, $c ];
 $obj->put( "ComposedOf", \@things );

Use "insertElement" and "removeElement" to add or remove elements from
a list.

=cut

#--------------------------------------------------------------------------

# another delegation to the session module, with a little bit of extra glue to
# allow multiple name=>value pairs to be specified.

sub put {   # put one or more properties
    my $obj = shift @_;
    while ( @_ ) {
	my $prop = shift @_;
	my $value = shift @_;

	throw "[1] Missing argument for InCharge::object::put"
	    unless( defined($obj) and defined($prop) and defined($value) );

	$obj->{_session}->put( $obj->{_class}, $obj->{_instance},
							    $prop, $value );
    }
    return;
}

#--------------------------------------------------------------------------

=item B<isNull>

 $boolean = $object->isNull();

Tests to see whether the object is present in the repository. TRUE means that
it is NOT present. FALSE means it IS.

=cut

sub isNull {
    my $obj = shift @_;
    return $obj->{_session}->instanceExists($obj->{_class}, $obj->{_instance} )
	    ? 0 : 1;
}

#--------------------------------------------------------------------------

=item B<invoke>

 reply = $object->invoke( $operation, ... arguments ... );

Invokes the named repository class operation on the object. The arguments
passed should be as expected by the operation. If the operation returns a
scalar value; the call should be called in a scalar context. If it returns an
array, it should be invoked in an array context.

Note that the preferred way of achieving the same result is to use the
operation name directly, thus the following are equivalent, but the latter is
preferred.

    $obj->invoke( "makePort", "1.0", "First port", "Port" );
    $obj->makePort( "1.0", "First port", "Port" );

Also, see the "invoke_t" method, described below.

=cut

#--------------------------------------------------------------------------

sub invoke {	# invoke an operation
    my ( $obj, $opname, @args ) = @_;

    return $obj->{_session}->invoke( $obj->{_class}, $obj->{_instance},
							    $opname, @args );
}

#--------------------------------------------------------------------------

=item B<invoke_t>

 ( $type, $value ) = $object->invoke_t( $operation, .. args .. )>

Invokes the named class operation on the object in the same way that "invoke"
(above) does, but invoke_t also returns the type of data returned by the call.
The data types are encoded as integer numbers, listed and explained in
L<InCharge::remote>. If the return is an array, then the "$value" will receive
a reference to the array. If the return is a scalar, then "$value" will hold
it.

=cut

#--------------------------------------------------------------------------

sub invoke_t {	# invoke an operation
    my ( $obj, $opname, @args ) = @_;

    return $obj->{_session}->invoke_t( $obj->{_class}, $obj->{_instance},
							    $opname, @args );
}

sub invoke_T {	# invoke an operation
    my ( $obj, $opname, @args ) = @_;

    return $obj->{_session}->invoke_T( $obj->{_class}, $obj->{_instance},
							    $opname, @args );
}

#--------------------------------------------------------------------------

=item B<insertElement>

 $obj->insertElement( $relation, @values[s] );

Inserts the specified objects into an object relationship, or inserts
structures into an ICIM table. One or more can be specified to be inserted.

For example; to insert 2 structures into an ICIM structure table, specify
the types and values like this..

 $obj->insertElement( "structTable",
    [   # record no 1
          [ "STRING", "One" ],      # field 1
          [ "INT", 32 ]             # field 2
    ],
    [   # record no 2
          [ "STRING", "Two" ],      # field 1
          [ "INT", 64 ]             # field 2
    ]
 );

To insert objects into a relationship, use ..

 $obj->insertElement( "ComposedOf", "Interface::IF-ether1" );

=cut

sub insertElement {
    my $obj = shift @_;

    return $obj->{_session}->insertElement( $obj, @_ );
}


#--------------------------------------------------------------------------

=item B<removeElement>

 $obj->removeElement( $relation, @item[s] );

removes the specified items from an object relationship. One or more items can
be specified to be removed.

 $obj->removeElement( "ComposedOf",
    "Interface::IF-ether1", "Interface::Loopback/0" );

 $obj->removeElement( "ComposedOf", @interfaces );

See "insertElement" for a more complete description of the syntax available
when using this function.

=cut

sub removeElement {
    my $obj = shift @_;

    return $obj->{_session}->removeElement( $obj, @_ );
}

#--------------------------------------------------------------------------

=item B<delete>

 $obj->delete( )

Deletes the specified item from the repository, but without performing any
clean-up of inter-object dependencies. Consider using the "remove" operation
(if one exists) instead for a more complete (cleaner) action.

=cut

sub delete {
    my $obj = shift @_;
    throw "[1] Wrong number of arguments for InCharge::object::delete"
	if (@_);
    return $obj->{_session}->deleteInstance( $obj->{_class},
							$obj->{_instance} );
}

#--------------------------------------------------------------------------

=item B<notify>

 $obj->notify( $event_name );

Notifies the specified event for the object.

    $objref->notify( "Unresponsive" );

=cut

sub notify {
    my ($obj, $event, $none) = @_;
    throw "[1] Wrong number of arguments of InCharge::object::notify.\nHINT: if you intended to access an operation called 'notify',\nthen you need to use the 'invoke' method to prevent name\nclashing with the 'notify' primitive"
	if (!defined($event) or defined($none));
    return $obj->{_session}->forceNotify(
	$obj->{_class},
	$obj->{_instance},
	$event,
	0,
	0
    );
}

#--------------------------------------------------------------------------

=item B<clear>

 $obj->clear( $event_name );

Clear the specified event for the object.

    $objref->clear( "Unresponsive" );

=cut

sub clear {
    my ($obj, $event, $none) = @_;
    throw "[1] Wrong number of arguments of InCharge::object::clear.\nHINT: if you intended to access an operation called 'clear',\nthen you need to use the 'invoke' method to prevent name\nclashing with the 'clear' primitive"
	if (!defined($event) or defined($none));
    return $obj->{_session}->forceNotify(
	$obj->{_class},
	$obj->{_instance},
	$event,
	0,
	1
    );
}

#--------------------------------------------------------------------------

=item B<countElements>

 $count = $obj->countElements( $relation )

Counts the number of elements in the given relationship, or throws an error if
$relation is not a relationship.

    $count = $obj->countElements( "ComposedOf" );

=cut

sub countElements {
    my ($obj, $relation, $none) = @_;

    throw "[1] Wrong number of arguments of InCharge::object::countElements"
	if (!defined($relation) or defined($none));

    return $obj->{_session}->countElements(
	$obj->{_class},
	$obj->{_instance},
	$relation
    );
}


#--------------------------------------------------------------------------

sub AUTOLOAD {
    my $obj = shift @_;
    if ( $AUTOLOAD =~ m/([^:]+$)/ ) {

	return $obj->invoke( $1, @_ );

    } else {
	throw "[12] Invalid procedure name";
    }
}

sub DESTROY { }

#--------------------------------------------------------------------------
# The code for virtualising InCharge::object references as nearly-OO objects.
# This is done using the perl "tie" mechanism, documented in detail in the
# perltie man page.

# We keep an internal note of the names of all the properties of every ICIM
# class we encounter, as we encounter them. This is so that we have the info
# needed to walk the hash keys using the FIRSTKEY/NEXTKEY logic (described in
# "man perltie".

my $keyhash = { };

sub _cache_hash_keys {
    my ( $ref ) = @_;
    my $class = $ref->{_class};

    return if (defined $keyhash->{$class}->{1});
    my @props = $ref->{_session}->getPropNames($ref->{_class});
    @props = sort @props;
    for ( my $i=0; $props[$i]; $i++ ) {
	$keyhash->{$class}->{$props[$i]} = $props[$i+1];
    }
    $keyhash->{$class}->{1} = $props[0];
}

sub TIEHASH {
    my ( $pkg, $hash ) = @_;
    return (bless $hash, $pkg);
}

sub FIRSTKEY {
    my ( $ref ) = @_;
    _cache_hash_keys( $ref );
    return $keyhash->{$ref->{_class}}->{1};
}

sub NEXTKEY {
    my ( $ref, $key ) = @_;
    _cache_hash_keys( $ref );
    return $keyhash->{$ref->{_class}}->{$key};
}

sub EXISTS {
    my ( $ref, $key ) = @_;
    _cache_hash_keys( $ref );
    return exists $keyhash->{$ref->{_class}}->{$key};
}

# hash vars with keys that start "_" are internal. We store them in the
# reference hash, but don't see them through "keys( )".  The special key "_"
# exposes the internal reference entirely.

sub FETCH {
    my ( $ref, $key ) = @_;

    if ( $key eq "_") {
	return $ref
    } elsif ( $key =~ m/^_/ ) {
	return $ref->{$key};
    } else {
	# we "eval" so that we get a NULL for a property we can't get - so
	# Dumper works. Anyway - this is "righter" for normal perl usage.
	return eval{ $ref->get( $key ); };
    }
}

sub STORE {
    my ( $ref, $key, $value ) = @_;

    # keys with leading underbars are genuine local hash keys

    if ( $key =~ m/^_/ ) {
	$ref->{$key} = $value;
    } else {
	$ref->put( $key, $value );
    }

    return $value;
}

sub DELETE {
    my ( $ref, $key ) = @_;

    throw "[11] Cant 'delete' properties from InCharge::object instances";
}

sub CLEAR {
    0;
}

# Hooks for Storable::dclone

my %saved_session = ( );

sub STORABLE_freeze {
    my ( $ref, $cloning ) = @_;
    my $session = $ref->{_session};
    $saved_session{"".$session} = $session;
    return $session.chr(0).$ref->{_class}.chr(0).$ref->{_instance};
}

sub STORABLE_thaw {
    my ( $obj, $cloning, $frozen ) = @_;
    my $chr0 = chr(0);
    my ( $session, $class, $instance ) = split( /$chr0/, $frozen );
    $obj->{_class} = $class;
    $obj->{_instance} = $instance;
    $obj->{_session} = $saved_session{ $session };
}

return 1;
__END__

=back

=cut

#### eof ####			    vim:ts=8:sw=4:sts=4:tw=79:fo=tcqrnol:noet:
