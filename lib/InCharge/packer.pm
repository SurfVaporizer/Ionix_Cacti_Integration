#+ packer.pm - rtns for (un)packing binary data for the wire-line protocol
#
# Copyright (c) 2003 System Management ARTS (SMARTS)
# All Rights Reserved.
#
# SMARTS provides this program 'as is' for educational and illustrative
# purposes only, without warranty or support.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/perlApi/perl/packer.pm#2 $
# $Source: /src/MASTER/smarts/perlApi/perl/packer.pm,v $
#

# History:
# 	Updated to provide platform-nonspecific implementation
# 	of 64 bit integers using Math::BigInt.
# 	Chris Lowth <chris.lowth@smarts.com>
# 	July 2004

package InCharge::remote;

use Math::BigInt;
use Math::BigFloat;		# For float range check


# Declare this additional constants not in default limits

use constant LLONG_MIN	=> -9223372036854775808;
use constant LLONG_MAX	=>  9223372036854775807;
use constant ULLONG_MAX	=> 18446744073709551615;


# Reference Constant values

#   UCHAR_MAX	    Math::BigInt(                        '255' );
#   SHRT_MIN	    Math::BigInt(                    '-32 768' );
#   SHRT_MAX	    Math::BigInt(                     '32 767' );
#   USHRT_MAX	    Math::BigInt(                     '65 535' );
#   LONG_MIN	    Math::BigInt(             '-2 147 483 648' );
#   LONG_MAX	    Math::BigInt(              '2 147 483 647' );
#   ULONG_MAX	    Math::BigInt(              '4 294 967 295' );
#
#   FLT_MIN	    Math::BigFloat(          '1.17549435e-38'  );
#   FLT_MAX	    Math::BigFloat(          '3.40282347e+38'  );
#   DBL_MIN	    Math::BigFloat( '2.22507385850720138e-308' );
#   DBL_MAX	    Math::BigFloat( '1.79769313486231571e+308' );
#   LDBL_MIN	    Math::BigFloat( '2.22507385850720138e-308' );
#   LDBL_MAX	    Math::BigFloat( '1.79769313486231571e+308' );



sub check_int ($) {
    &throw("[6] Not an integer value - '$_[0]'")
	unless ( $_[0] =~ m{\s*-?\s*[0-9]+\s*$} );
}

# ---- 8-but unsigned character
sub unpack_uchar ($) { return unpack( "C", $_[0] ); }
sub pack_uchar ($) {
    check_int( $_[0] );
    my $n = sprintf "%D", $_[0];

    throw ("[6] Unsigned char $_[0] out of range.")
	unless ($n >= 0 and $n <= UCHAR_MAX);

    return pack( "C", $_[0] );
}

# ---- 16bit unsigned integer
sub unpack_i16u ($) { return unpack( "n", $_[0] ); }
sub pack_i16u ($) {
    check_int( $_[0] );
    my $n = sprintf "%D", $_[0];

    throw ("[6] Unsigned short $_[0] out of range.")
	unless ($n >= 0 and $n <= USHRT_MAX);

    return pack( "n", $_[0] );	    
}

# ---- 16 bit signed integer
sub unpack_i16s ($) {
    my $n = unpack_i16u( $_[0] );
    return ($n >= 0x8000 ) ? ($n - 0xffff - 1) : $n;
}
sub pack_i16s ($) {
    check_int( $_[0] );
    my $n = sprintf "%D", $_[0];

    throw ("[6] Signed short $_[0] out of range.")
	unless ($n >= SHRT_MIN and $n <= SHRT_MAX); 

    return pack( "n", $_[0] );	   # Directly call this instead of passing it
				   # to pack_i16u. This is to separate the
				   # range checking for the two types.
}

# ---- 32bit unsigned long integer
sub unpack_i32u ($) { return unpack( "N", $_[0] ); }
sub pack_i32u ($) {
    check_int( $_[0] );

    my $n = sprintf "%D", $_[0];
    $n = Math::BigInt->new($n);

    throw ("[6] Unsigned integer $_[0] out of range.")
	unless ($n >= 0 and $n <= ULONG_MAX);

    return pack( "N", $_[0] );
}

# ---- 32bit signed long integer
sub unpack_i32s ($) {
    my $n = unpack( "N", $_[0] );
    return ($n >= 0x80000000 ) ? ($n - 0xffffffff - 1) : $n;
}
sub pack_i32s ($) {
    check_int( $_[0] );

    my $n = sprintf "%D", $_[0];
    $n = Math::BigInt->new($n);

    throw ("[6] Signed Integer $_[0] out of range.")
	    unless ($n >= LONG_MIN and $n <= LONG_MAX);

    return pack( "N", $_[0] );	    # Directly call this instead of passing it
				    # to pack_i16u. This is to separate the
				    # range checking for the two types.


}

# ---- 64bit unsigned very long integer

sub unpack_i64u ($) {
    my ( $n ) = @_;
    throw("[9] bad data size for i64u") unless (length($n) == 8);
    my @n = unpack( "C*", $n );
    my $rtn = Math::BigInt->bzero();
    while ( @n ) {
	    $rtn->blsft(8);
	    $rtn->badd(shift @n);
    }
    return $rtn;
}

sub unpack_i64s ($) {
    my ( $n ) = @_;
    throw("[9] bad data size for i64u") unless (length($n) == 8);
    my @n = unpack( "C*", $n );
    my $neg = 0;
    if ($n[0] > 127) { $neg = 1; }
    my $rtn = Math::BigInt->bzero();
    if ( $neg ) {
	    while ( @n ) {
		    $rtn->blsft(8);
		    $rtn->badd((shift @n) ^ 255);
	    }
	    $rtn->badd(1);
	    $rtn->bneg();
    } else {
	    while ( @n ) {
		    $rtn->blsft(8);
		    $rtn->badd(shift @n);
	    }
    }
    return $rtn;
}

sub pack_i64s ($) {

    my ( $n ) = @_;
    my $p = "";

    $n = Math::BigInt->new($n);

    throw ("[6] Long Integer $n out of range.")
    	unless ($n >= LLONG_MIN and $n <= LLONG_MAX);

    for (my $i = 0; $i < 8; $i ++) {
	my $n2 = Math::BigInt->new($n);
	$n2->band( 0xff );
	$p = chr($n2).$p;
	$n->brsft(8);
    }


    return $p;

}

sub pack_i64u ($) {

    # Add this here so we don't have to call pack_i64s
    my ( $n ) = @_;
    check_int( $n );
    my $p = "";

    $n = Math::BigInt->new($n);

    throw ("[6] Unsigned long $n out of range.\n")
    	     unless ($n >= 0 or $n <= ULLONG_MAX );

    # Add this here so we don't have to call pack_i64s
    for (my $i = 0; $i < 8; $i ++) {
    	my $n2 = Math::BigInt->new($n);
    	$n2->band( 0xff );
    	$p = chr($n2).$p;
    	$n->brsft(8);
    }

    return $p;

}







# ---- Floating point

# we need to discover which native floating point format to use..
# (this is pretty ugly stuff!)
my $native_float_format = 0;
my $n = join( ":", unpack( "C*", pack( "f", 123456789 ) ) );
if ( $n eq "163:121:235:76" ) {
    $native_float_format = 1;
} elsif ( $n eq "76:235:121:163" ) {
    $native_float_format = 2;
}

sub pack_float32 ($) {

    # Pack the float into its HOST binary format - as an array of bytes
    my @b = unpack( "C*", pack( "f", $_[0] ) );

    # Check that this gives us 4 bytes
    throw("[9] bad data size for float32") unless ($#b == 3);

    # Pack the bytes into the right order for the NETWORK representation. Throw
    # an error if we dont know how.
    if ( $native_float_format == 1 ) {
	return pack( "CCCC", $b[3], $b[2], $b[1], $b[0] );
    } elsif ( $native_float_format == 2 ) {
	return pack( "CCCC", $b[0], $b[1], $b[2], $b[3] );
    } else {
	throw("[9] Unsupported native floating point number format");
    }
}

sub unpack_float32 ($) {

    # Unpack the NETWORK data into 4 bytes
    my @b = unpack( "C*", $_[0] );

    # Check that we really have got 4 bytes
    throw("[9] bad data size for float32") unless ($#b == 3);

    # Map the bytes into a HOST representation of a floating point number -
    # using the relevant byte ordering. Throw an error if we don't know how.
    if ( $native_float_format == 1 ) {
	return unpack( "f", pack( "CCCC", $b[3], $b[2], $b[1], $b[0] ) );
    } elsif ( $native_float_format == 2) {
	return unpack( "f", pack( "CCCC", $b[0], $b[1], $b[2], $b[3] ) );
    } else {
	throw("[9] Unsupported native floating point number format");
    }
}

# TODO: Verify byte order is correct!
sub pack_float64 ($) {

    # Pack the float (double) into its HOST binary format - as an array of bytes
    my @b = unpack( "C*", pack( "d", $_[0] ) );

    # Check that this gives us 8 bytes
    throw("[10] bad data size for float64") unless ($#b == 7);

    # Pack the bytes into the right order for the NETWORK representation. Throw
    # an error if we dont know how.
    if ( $native_float_format == 1 ) {
	return pack( "CCCCCCCC", $b[7], $b[6], $b[5], $b[4], $b[3], $b[2], $b[1], $b[0] );
    } elsif ( $native_float_format == 2 ) {
	return pack( "CCCCCCCC", $b[0], $b[1], $b[2], $b[3], $b[4], $b[5], $b[6], $b[7] );
    } else {
	throw("[10] Unsupported native floating point (double) number format");
    }
}

# TODO: Verify byte order is correct!
sub unpack_float64 ($) {

    # Unpack the NETWORK data into 8 bytes
    my @b = unpack( "C*", $_[0] );

    # Check that we really have got 8 bytes
    throw("[10] bad data size for float64") unless ($#b == 7);

    # Map the bytes into a HOST representation of a floating point number -
    # using the relevant byte ordering. Throw an error if we don't know how.
    if ( $native_float_format == 1 ) {
	return unpack( "d", pack( "CCCCCCCC", $b[7], $b[6], $b[5], $b[4], $b[3], $b[2], $b[1], $b[0] ) );
    } elsif ( $native_float_format == 2) {
	return unpack( "d", pack( "CCCCCCCC", $b[0], $b[1], $b[2], $b[3], $b[4], $b[5], $b[6], $b[7] ) );
    } else {
	throw("[10] Unsupported native floating point (double) number format");
    }
}

1;

#### eof ####			    vim:ts=8:sw=4:sts=4:tw=79:fo=tcqrnol:noet:
