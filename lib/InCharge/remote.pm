#+ remote.pm - implement core remote InCharge access mechanism for Perl
#
# Copyright (c) 2003 System Management ARTS (SMARTS)
# All Rights Reserved.
#
# SMARTS provides this program 'as is' for educational and illustrative
# purposes only, without warranty or support.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/perlApi/perl/remote.pm#4 $
# $Source: /src/MASTER/smarts/perlApi/perl/remote.pm,v $
#

package InCharge::remote;

use IO::Handle;
use POSIX;
use Storable qw(dclone);
use Data::Dumper;
use InCharge::packer;
use InCharge::primitiveTable;
use Config;

#$env_flow_val = uc($ENV{"SM_DISABLE_FLOW_WRAPPER"});
$env_flow_val = 1;

$NO_FLOW=0;
if ( $Config{"useshrplib"} eq "false" ) {
      $NO_FLOW=1;
} else {
  if( ($env_flow_val eq "YES") || ($env_flow_val eq "Y") || ($env_flow_val eq "1") ){
    $NO_FLOW=1;
  } else {
    # Make sure it is version 5.8.8 to allow the flow...
    eval "require 5.8.8;" or $NO_FLOW=1;
  }
}

our $RET_NOK = -1;

our $VERSION = '2.01';

our $showErrorsOnStderr = 0;	# set to '1' to force all errors to be printed
				# on stderr, even if "caught" with eval{ .. }

our $dump_packets = 0;

# This is set if you call get_T rather than get_t (etc).
our $addTypesToAnyvalArrays = 0;

# Collection of HASHes, indexed by fileno( socket )
our %cache = ( );   # hash for "cached" values (like: function return
		    # type) that we dont need to ask more than once
		    # about.

our @timeout = ( ); # configured timeout for the socket (seconds)

our @broken = ( );  # if the connection is "broken" - a reason string
		    # is stored here for the socket handle.

our @version = ( ); # InCharge server version number in use. This is
		    # (major * 1000) + minor.

our @inbuff = ( );  # Buffer used when reading data from the wire. This
		    # hold data not yet consumed.

our @rxbuff = ( );  # Buffer that contains data read so far from the wire
		    # while handling the current primitive.

our @read_buffer = ( );

#---------------------------------------------------------------
# In the following tables, we define a set of single-character data type
# specifiers.

%typeCodeTable = (
    0  => [ "V",    "VOID" ],
    1  => [ "!",    "ERR" ],
    2  => [ "B",    "BOOLEAN" ],
    3  => [ "I",    "INT" ],
    4  => [ "i",    "UNSIGNED" ],
    5  => [ "L",    "LONG" ],
    6  => [ "l",    "UNSIGNEDLONG" ],
    7  => [ "W",    "SHORT" ],
    8  => [ "w",    "UNSIGNEDSHORT" ],
    9  => [ "F",    "FLOAT" ],
    10 => [ "D",    "DOUBLE" ],
    11 => [ undef, undef ],
    12 => [ ".",    "CHAR" ],
    13 => [ "S",    "STRING" ],
    14 => [ "O",    "OBJREF" ],
    15 => [ "r",    "OBJCONSTREF" ],
    16 => [ "[B",   "BOOLEAN_SET" ],
    17 => [ "[I",   "INT_SET" ],
    18 => [ "[i",   "UNSIGNED_SET" ],
    19 => [ "[L",   "LONG_SET" ],
    20 => [ "[l",   "UNSIGNEDLONG_SET" ],
    21 => [ "[W",   "SHORT_SET" ],
    22 => [ "[w",   "UNSIGNEDSHORT_SET" ],
    23 => [ "[F",   "FLOAT_SET" ],
    24 => [ "[D",   "DOUBLE_SET" ],
    25 => [ undef, undef ],
    26 => [ "[.",   "CHAR_SET" ],
    27 => [ "[S",   "STRING_SET" ],
    28 => [ "[O",   "OBJREF_SET" ],
    29 => [ undef, undef ],
    30 => [ "[*",   "ANYVALARRAY" ],
    31 => [ "[@",   "ANYVALARRAY_SET" ],
    50 => [ "[#",   "ANYVALARRAY" ],
    51 => [ "[~",   "ANYVALARRAY_SET" ] # not a real type - needed by "proxy"
					# an array of anyval arrays, with types.
);

my %icode2name = (	# map internal codes to names
    "#" =>  "ANYVAL",
    "*" =>  "VALUE"
);

#------------------------------------------------------------------
# compoundTypeTable maps the single-letter formats to their fuller
# specifications. A ":" at the start of the string means that the the structure
# should be returned as an array reference. The ":" has no impact when the
# structure is used as a primitive argument.


my %compoundTypeTable = (
    "E" => ":OS",	    # eventName
    "e" => "ISSS",	    # event or property choice
    "N" => "ii",	    # notification parameters
#   "P" => "III",	    # accessor polling parameters
    "C" => "IIFFFFIBB",	    # correlation parameters
    "v" => "ILSSS*",	    # observer event
#   "n" => "SSSS",	    # snmp access info
    "T" => ":ISSS",	    # thread
    "Y" => ":IFOS",	    # symptom
    "@" => "[*",	    # array of anyvals (no types)
    "~" => "[#",	    # Array of anyvals with types
    "p" => "S*",	    # Property Name And Value (no types)
    "P" => "S#",	    # Property Name And Value (with types)
    "h" => ":SSB",	    # Class hierarchy element
    "s" => ":IiSSIFSSS",    # Symptom data
);
my $compoundTypeTableKeyRegex = "[".join( "", sort keys %compoundTypeTable )."]";

### s/$compoundTypeTableKeyRegex/$compoundTypeTable{$1}/g;

# The callAliases table provides more familiar names for some of the remote
# call stubs. Users of ASL and DMCTL are (for example) familiar with the
# command "invoke" instead of "invokeOperation".

my %callAliases = (
    eventIsExported	    => "getEventExported",
    "exists"		    => "instanceExists",
    execute		    => "executeProgram",
    getAttributes	    => "getAttributeNames",
    getEvents		    => "getAllEventNames",
    getInstances	    => "getClassInstances",
    getModels		    => "getLibraries",
    getOperationArgumentType=> "getArgType",
    getOpArgType	    => "getArgType",
    getOperationArguments   => "getOpArgs",
    getOperationDescription => "getOpDescription",
    getOperationReturnType  => "getOpReturnType",
    getOperations	    => "getOpNames",
    getOperationFlag	    => "getOpFlag",
    getProperties	    => "getPropNames",
    getPropertyDescription  => "getPropDescription",
    getPropertyType	    => "getPropType",
    getRelations	    => "getRelationNames",
    invoke		    => "invokeOperation",
    invoke_t		    => "invokeOperation_t",
    invoke_T		    => "invokeOperation_T",
    loadModel		    => "loadLibrary",
    ping		    => "noop",
    purgeObserver	    => "deleteObserver",
    "shutdown"		    => "quit",
);

#------------------------------------------------------------------

my (
    @data_types,	# map type numbers to name
    %data_types,	# map type names to numbers
);

#------------------------------------------------------------------
# convert a datatype code number to the equivalent descriptive 
# string, or visaversa.
# So:
#   InCharge::remote::TYPE( 13 )
# returns:
#   "STRING"

sub TYPE ($) {
    my $what = shift @_;
    if (isdigit( $what )) {
	return $data_types[$what];
    } else {
	$what =~ s/^MR_//;
	return $data_types{$what};
    }
}

# When this module is loaded into memory, do some quick pre-parsing
# of the datatypes tables to provide info we need later in hashes
# so that we can get to it with doing explicit searches (for speed).
foreach my $key ( keys %typeCodeTable ) {
    my ($val, $name) = @{$typeCodeTable{$key}};
    $data_types[$key] = $name	if (defined $key);
    $data_types{$name} = $key	if (defined $name);
    $icode2name{$val} = $name	if (defined $val);
}


# forward declarations, where "-w" shows they are needed.
sub recvValue ($$$);
sub encodeValue ($$$$);


$lastFileno=1;
sub getFlowFileno($){
 my ($filehandle) = @_;

   if ( $NO_FLOW)
   {
       $Ret = fileno($filehandle);
   }
   else
   {
       if(! defined $flowFileno{$filehandle})
       {
           if( $Config{osname} eq "MSWin32" )
           {
               $flowFileno{$filehandle} = $lastFileno;
               $lastFileno ++;
           }
           else
           {
               my $ret_handle = $filehandle->flowPhysGetPhysicalHandle();
               
               if( $ret_handle == $RET_NOK)
               {
                  throw ("[13] No socket opened for this session!\n");
               }

               my $localFileno  = $ret_handle;
               $flowFileno{$filehandle}= $localFileno;
           }
       }
       $Ret = $flowFileno{$filehandle};
   }
   return ($Ret);
}

#------------------------------------------------------------------------------
# throw an error, in such a way that the line in the user script from which the
# call throwing the error is given as the source of the error. This is how any
# errors detected by the RPA are raised. It's a "die" really but with some
# message mangling logic wrapped round it to make the resulting message more
# useful to the user.

sub throw {
    my $n = 0;

    my ( $pkg, $file, $line );

    # Walk backwards through the call stack, looking at our caller, and our
    # caller's caller .. etc - until we find a call from a package that isnt an
    # InCharge::* one. We assume that this is user script call point (yes - the
    # logic can be fooled!).
    for ( ; ; ) {
	( $pkg, $file, $line ) = caller($n);
	last if ( $n > 20 or $pkg !~ m/^InCharge::/ );
	$n ++;
    }

    # Build the "throw( ... )" arguments into a single string.
    my $msg = join(" ", @_);

    # Follow the usual perl convention that error messages that end with a
    # newline are "thrown" without change, but that others have the filename
    # and line number nailed onto the end.
    unless ( $msg =~ m/\n$/s ) {
	$msg .= ", stopped at $file line $line\n";
    }

    # If the user wants messages on STDERR even if they are being caught by an
    # "exec { .. }" syntax, then show it to him now.
    print STDERR "InCharge::session::throw -- $msg\n" if ($showErrorsOnStderr);

    # Finally - give up the ghost in the usual perl manner.
    die $msg;
}

#------------------------------------------------------------------------------
# Hexdump a buffer - useful for debugging.

sub hexdump {
    my ( $buf ) = @_;
    my @buf = unpack( "C*", $buf );
    while ( @ buf ) {
	my $hex = "";
	my $asc = "";
	for (my $i=0; $i<16 && @buf; $i ++) {
	    my $c = shift @buf;
	    $hex .= sprintf( "%02x ", $c);
	    $asc .= ($c < 32 || $c > 127) ? "." : chr($c);
	}
	print sprintf( "%-48.48s : %-16.16s\n", $hex, $asc);
    }
}

#------------------------------------------------------------------------------
# get the class to which a named instance belongs.

sub _getInstanceClass ($$) {
    # Put arguments into scalars
    my ( $handle, $instance ) = @_;

    # Ask the domain manager to tell us the class name.
    return InCharge::remote::get(
	$handle, "MR_Object", $instance, "CreationClassName"
    );
}

#-------------------------------------------------------------------------
# _getObject takes an object reference from the specified argument array and
# returns the class and instance names in a 2-element array.
#
# Various possible incoming syntaxes are handled.
#
# If the first argument in the array looks like "Class::Instance", then we
# split it into it's two parts, and return them. If it doesn't look like that,
# we simply return it and the second argument.  In both cases, the used
# arguments are "shift"ed off the array in the process.
#
# This is where the different object naming syntaxes that can be used by RPA
# primtives are handled. For the user perspective - refer to "$object" in the
# "DATA TYPES" section of "primitives.pdf".

sub _getObject ($$$) {
    my (
	$handle,    # handle of socket for talking to server
	$aref,	    # reference to the array, where the object
		    # info is expected to be held.
	$forceclass # should we insist on the class being
		    # specified (boolean) ?
    ) = @_;

    # $aref can refer to an array containing one of a number of different ways
    # of specifying an object. We go through the process of trying to identify
    # which.

    # Start by assuming that $aref->[0] is a class name. We may change our mind
    # later.
    my $class = shift @{ $aref };
    my $instance;

    # If we have been passed an InCharge::object reference, just
    # pass it on.
    if (ref $class eq "InCharge::object") {
	return ($class->{_class}, $class->{_instance});
    }

    # If we have been passed a null class, but non-null instance, then go to
    # the server to find the relevant class name. We then return the discovered
    # class name and specified instance name.
    if (!defined($class) && @{ $aref } ) {
	my $instance = shift @{ $aref };

	# if instance is not specified - return empty strings. This
	# is VALID if the class is optional.
	return ( "", "" ) if (!($instance) and !$forceclass);

	# check the class HAS been specified if we are requring it.
	throw "[6] Class cannot be omitted from object name" if ($forceclass);

	# Check that an instance has been specified.
	throw "[6] Empty object name (after undef class)" unless ( $instance );

	# ask the server for the class name
	$class = _getInstanceClass( $handle, $instance );

	# return the class and instance
	return ( $class, $instance );
    }

    # If we have been passed a string like "[class]::instance", we (as above)
    # go to the server to get the name of the class.

    if ( $class =~ /::/ ) {
	# Split the string into class and instance by the first "::" it
	# contains.
	( $class, $instance ) = ( $class =~ m/^\s*(.*?)\s*::\s*(.*?)\s*$/ );

	# if instance is not specified - return empty strings. This
	# is VALID if the class is optional.
	return( "", "" ) if ( $class eq "" and $instance eq "" and
								!$forceclass);

	# If we dont have class - get it from the server.
	if ( $class eq "" ) {
	    throw "[6] Class cannot be omitted from object name"
							if ($forceclass);
	    throw "[6] Empty object name (no instance after '::')"
							unless ( $instance );
	    $class = _getInstanceClass( $handle, $instance );
	}

	# Make sure we have at least an instance name
	throw "[6] Instance omitted from object name" unless ( $instance );

	# return the class and instance
	return ( $class, $instance );
    }

    # If we have only got one string (at the end of the argument list), then
    # (as above) get the class name and return both.
    if ( defined( $class ) and $#{ $aref } == -1 ) {
	throw "[6] Class cannot be omitted from object name" if ($forceclass);
	$instance = $class; $class = "";
	return ( "", "" ) if ( $instance eq "" );
	throw "[6] Empty object name (empty instance)" unless ( $instance );
	$class = _getInstanceClass( $handle, $instance );
	return ( $class, $instance );
    }

    # Otherwise we assume we have been passed at least two strings
    $instance = shift @{ $aref };

    throw "[6] Empty object name (missing class or instance)"
					    unless ( $class or $instance );
    throw "[6] Class omitted from object name" unless ( $class );
    throw "[6] Instance omitted from object name" unless ( $instance );

    return ( $class, $instance );
}

#------------------------------------------------------------------------
# AUTOLOAD is a standard perl subroutine, used to resolve calls to subs that
# are not explicitly named in the module. We use it to catch these calls, and
# (where appropriate) resolve then to the ICIM protocol exchange of the same
# name. This allows a script to say (for example) ..
#
#   @list = InCharge::remote::getClasses( $handle );
#
# in place of ..
#
#   @list = InCharge::remote::primitive( "getClasses", $handle );
#
# Note that the InCharge::session module takes this one step further, and
# allows the ASL-like syntax..
#
#   @list = $session->getClasses();
#
# Refer to the "perlsub" man page for details of the AUTOLOAD mechanism.

sub AUTOLOAD {
    if ( $AUTOLOAD =~ m/([^:]+$)/ ) {
	return primitive( $1, @_ );
    } else {
	throw "[12] Invalid InCharge primitive name: '$AUTOLOAD'";
    }
}

sub DESTROY {
}

#------------------------------------------------------------------------
# Initialize the cached values hash for a specified socket number. This gets
# called by the InCharge::session module when setting up a new connection.

sub initCache ($) {
    my ( $sock ) = @_;

    delete $cache{getFlowFileno($sock)};
    
}

#------------------------------------------------------------------------

sub initConnection {
    my ( $sock, $timeout ) = @_;

    my $fileno = getFlowFileno($sock);

    $version[$fileno] = undef;
    $timeout[$fileno] = $timeout;
    $broken[$fileno] = undef;
    $read_buffer[$fileno] = undef;
}

#------------------------------------------------------------------------

sub isBroken {
    my ( $sock ) = @_;
    
    return defined $broken[getFlowFileno($sock)];
    
}

#------------------------------------------------------------------------

# (void) collectResultCode( $sock, $callname )
#
# This the first thing to be done when receiving the reply to a request sent to
# the server. 
# It reads the 1st byte of the reply message, and if this indicates
# an error - the error message string is also read and "thrown". 
# If the 1st byte indicates success, then the function simply returns.
#
# $sock      is the handle used for reading data sent to us.
# $callName  is the name of the primitive we are processing. 
#            It is used when displaying any error message that 
#            needs to be seen.
#
#
#------------------------------------------------------------------------

sub collectResultCode {

    my ( $sock, $callName, $fileno ) = @_;

    my $result = readSock( $sock, $callName, 1 );

    if ( $result eq "\1" ) {
	my $errMsg = recvValue( $sock, "${callName}::error", "S" );
	if ($dump_packets) {
	    print "==== server -> perl\n";
	    hexdump( $rxbuff[$fileno] );
	}
	$errMsg =~ s/[\s\r\n]*$//s;
	throw "[15] $errMsg";
    }

    if ( $result ne "\2" ) {
	if ($dump_packets) {
	    print "==== server -> perl\n";
	    hexdump( $rxbuff[$fileno] );
	}
	$broken[$fileno] ="[9] Unexpected result type returned by DM";
	throw $broken[$fileno];
    }
}

#------------------------------------------------------------------------
# RESULT = primitive( $callName, $socket, @arguments )
#
# This is the main entry point for all the ICIM protocol remote calls listed in
# the primitiveTable. This gets called by the AUTOLOAD function when an unknown
# InCharge::remote function is called. So a function call like...
#
#   @list = InCharge::remote::getInstances( $socket, "Router" );
#
# Resolves (via perl's AUTOLOAD feature) to...
#
#   @list = InCharge::remote::primitive( "getInstances", $socket, "Router" );
#
# Note that the InCharge::session module performs some further simplification,
# allowing syntaxes like the following to be used (this is the normal syntax
# employed by user scripts) ...
#
#   @list = $session->getInstances( "Router" );
#
# See session.pm for details.
#
#
#------------------------------------------------------------------------
sub primitive ($$@) {
    # strip 1st 2 arguments off the stack, leaving the rest in place. What is
    # left is the argument list for the primitive itself.

    local $addTypesToAnyvalArrays;

    my $callName = shift @_;
    my $sock = shift @_;

    # Note the unix file number for the socket (even NT knows
    # about this idea).

    my $fileno = getFlowFileno($sock);


    #   throw "[2] Internal error - wrong context for 'DESTROY'"
    #	if ($callName eq "DESTROY");

    # Check the primitive alias names table, and map to the
    # real name if a match is found.
    if (defined $callAliases{$callName}) {
	$callName = $callAliases{$callName};
    }

    # A mini "con trick" follows..
    #
    # If the primitive name ends with _T, then we set the temporary flag
    # "addTypesToAnyvalArrays" to cause the returned data to include type
    # codes embedded within the structure itself.  We then change from _T to _t
    # to work with the primitive as declared in the %primtiveTable.

    if ( $callName =~ m{_T$} ) {
	# Since we use "local"; perl will restore this
	# variable to its old setting when this subroutine
	# ends - neat huh?
	$addTypesToAnyvalArrays = 1;
	$callName =~ s{_T$}{_t};
    }

    # Pull procedure call details from the primitiveTable, and throw
    # an error if we dont find it there.
    my $callInfo = $primitiveTable{$callName};
    throw "[12] InCharge primitive '$callName' is unknown"
						unless (defined $callInfo);
    my ( $code, $argTypes, $rtnTypes, $cacheflag, $version, $mappedArgTypes )
							    = @{$callInfo};

    # Check that we are actually connected to a server.
    throw "[10] Not attached to an InCharge domain manager"
						    unless (defined $sock);

    # Check that the primitive is known by this version of the protocol
    throw "[12] Primitive '$callName' not supported"
	if ( $version[$fileno] != -1 and $version[$fileno] < $version );

    # Expand and check number of object arguments. First, we map the compound
    # types from the argTypes in the primitives table. We do this only once per
    # primitive (ie we save the result of the mapping back into the table).
    if (defined $mappedArgTypes) {
	$argTypes = $mappedArgTypes;
    } else {
	$argTypes =~ s/($compoundTypeTableKeyRegex)/$compoundTypeTable{$1}/eg;
	$argTypes =~ s/://g;
	$callInfo->[5] = $argTypes;
    }

    my @t = split( //, $argTypes );
    my @v = ( );
    my $types = "";

    while ( @t ) {
	throw("[1] Too few arguments for '$callName'")
	    unless ( @_ );
	my $t = shift @t;
	if ( $t eq "[" ) {
	    $types .= "[" . shift(@t);
	    push @v, shift @_;
	} elsif ( $t eq "O" ) {
	    my ( $class, $inst ) = _getObject($sock, \@_, 0);
	    $types .= "SS";
	    push @v, $class, $inst;
	} elsif ( $t eq "J" ) {
	    my ( $class, $inst ) = _getObject($sock, \@_, 1);
	    $types .= "SS";
	    push @v, $class, $inst;
	} else {
	    $types .= $t;
	    push @v, shift @_;
	}
    }

    throw("[1] Too many arguments for '$callName'")
	if ( @_ );

    $argTypes = $types;
    @_ = @v;

    my @rtn = ( );	# value[s] that the primitive returns
    my $ref = undef;	# cache hash branch reference
    my $last = undef;	# cache end-of-the-branch key
    my $cachehit = 0;	# boolean: have we got good data from in-memory cache?

    # Get the data from our cache (if it's there). The logic here is to navigate
    # the cache hash tree until we find the "leaf node" at the end. Then note
    # the reference to the parent branch such that $ref->{$last} points to it.
    # If we find an existing leaf, set the $cachehit flag, otherwise just create
    # all the branches need to get there.
    if ( $cacheflag ) {
	$ref = \%cache;
	my @keys = ( $fileno, $callName, @_ );
	$last = pop( @keys );
	foreach ( @keys ) {
	    unless (defined $ref->{$_}) {
		$ref->{$_} = { };
	    }
	    $ref = $ref->{$_};
	}
	if (defined $ref->{$last}) {
	    # we found the value we want cached, so
	    # take note.
	    @rtn = @{$ref->{$last}};
	    $cachehit ++;
	}
    }

    # If we DID NOT get a hit on the cache (possibly because the primitive is
    # not a "cacheable" one), do the real work of exchanging a request and reply
    # with the server.

    unless ($cachehit) {

	# build the command (request) packet. Remember that @_ still contains
	# the primitive arguments?

	# Clone a copy so our "shift"ing logic doesnt edit the input args.

	my $txbuff =
	    pack_i32s( $code )
	    . encodeValues( $sock, $callName, $argTypes, \@_ );

	if ($dump_packets) {
	    print "==== perl -> server\n";
	    hexdump( $txbuff );
	}

	# If, after the encoding is complete there are still some left in @_
	# then the user gave us too many - so gripe!

	throw("[1] Too many arguments for InCharge primitive '$callName'")
	    if ( @_ > 0 );

	# flush the output stream so that the server gets our request.
	throw $broken[$fileno] if ( $broken[$fileno] );

	if($NO_FLOW)
	{
		print $sock $txbuff;
		$sock->flush();
	}
        else{
     	     $sock->flowClearInputBuffer();
    	     $sock->flowWrite($txbuff, length($txbuff));

    	     $flushRet = $sock->flowFlush();
    	     if($flushRet == $RET_NOK)
             {
                 throw "[13] Impossible to flush, connection lost!\n";
             }
        }

	$inbuff[$fileno] = undef;

	# Wipe the scratchpad in which we'll accumulate the
	# reply message we get back.
	$rxbuff[$fileno] = "";

	# Get the result code (report an error if we got one)
	collectResultCode( $sock, $callName, $fileno );

	# Now collect the reply values the server has sent us.
	@rtn = recvValues( $sock, $callName, $rtnTypes );

	if ( $dump_packets ) {
	    print "==== server -> perl\n";
	    hexdump( $rxbuff[$fileno] );
	}

	# If our earlier scan of the cache indicated that this was a cacheable
	# call, then save the return values for later retrieval.
	if ( $cacheflag ) {
	    $ref->{$last} = \@rtn;
	}
    }

    # Now we know what the primitive has returned so we can return them to our
    # caller - doing some return type simplification along the way.

    # if the primitive returns a single array reference, resolve it to the
    # actual array content for convenience.
    if (wantarray && $#rtn == 0 && ref($rtn[0]) eq "ARRAY" ) {
	return @{ $rtn[0] };
    }

    # Otherwise - in an array context, return the result(s) as an array.
    return @rtn if (wantarray);     # array context

    # In a scalar context, with just one return value - return it.
    return $rtn[0] if ($#rtn == 0);	# one reply in scalar context

    # In a scalar context, with no results available, return "undef"
    return undef if ($#rtn < 0);	# no replies in scalar context

    # In all other situations, return a reference to the result list. This
    # will occur when the call is made in a scalar context, and there is
    # more than one return value to pass back.
    return \@rtn;
}

#--------------------------------------------------------------------------
# $version = getPrimitiveVersion( $primitive_name )
#
# Return the primitive version or -1 if the primitive
# is not found
#
# 
# It uses the $primitiveTable to look for the primitive
#

sub getPrimitiveVersion {
    my ( $callName ) = @_;

	# First verify if the primitive name has an alias
    my $pname = $callAliases{$callName};

	# Use the primitive name ($callName) if there is no alias
    $pname = $callName unless ($pname);

    $pname =~ s{_T$}{_t};

	# look for the row in primitive table
    my $info = $primitiveTable{$pname};
    return (defined $info) ? $info->[4] : -1;
}

#--------------------------------------------------------------------------
# $buffer = encodeValues( $sock, $callname,  $argtypes, $args )
#
# This function takes a list of arguments that were passed to a primitive and
# uses the $argtypes string as a specification of how these should be encoded
# into a buffer for transmssion over the network to the server.  As we go
# through the list of arguments and types, we remove the ones we have processed
# from the @{$args} array.
#
# We make extensive use of the "encodeValue" (singular) call here.
#
# $sock     is the socket handle for the connection with the server. this
#	    is needed in case an ICIM object reference is given to us that
#	    needs a visit to the server to determine the class of.
#
# $callName is the name of the primitive. This is used to help dislaying
#	    useful error messages if things dont work out.
#
# $argtypes is a string of type characters (see %typeCodeTable and
#	    %compoundTable for the valid codes) that tells us how to
#	    encode the values held in @{$args}.
#
# $args     is a reference to an array that contains the arguments that
#	    have been used when calling the primitive in question.


sub encodeValues ($$$$) {
    my ( $sock, $callName, $argTypes, $args ) = @_;

    # split the argtypes string into an array of characters to make it easier to
    # iterate over.

    my @argTypes = split( //, $argTypes );
    my $buff = "";
    while ( @argTypes ) {
    
		my $argType = shift @argTypes;
		
		next if ( $argType eq ":" );

		throw "[1] Missing argument for InCharge primitive '$callName'"
	      unless ( @{$args} );

		if ( $argType eq "[" ) {
		
		    my $array = shift @{$args};
		    
		    throw "[6] Array argument expected for primitive '$callName'"

			unless (ref($array) eq "ARRAY");
			
		    # Clone the array so we work on a copy - thus preventing an
		    # unintentional editting of the input array in place.
		    $array = dclone( $array );
		    my $type = shift @argTypes;
		    my $n = $#{ $array } + 1;

		    $buff .= pack_i32s( $n );

		    for ( my $i = 0; $i < $n; $i ++ ) {
			  $buff .= encodeValue( $sock, $callName, $type, $array );
		    }
		    
		} 
		elsif ( $argType eq "I" ) {
		    $buff .= pack_i32s( shift @{ $args } ); # for speed!
		} 
		else {
		    $buff .= encodeValue( $sock, $callName, $argType, $args );
	    }
	    
    }
    return $buff;
}

#--------------------------------------------------------------------------
# $buffer = encodeValue( $sock, $callname, $type, $values )
#
# Encodes the value[s] as defined by the $type character. See encodeValues()
# above for details of how this is used.

sub encodeValue ($$$$) {
    my ( $sock, $callName, $type, $values ) = @_;

    throw "[1] Missing argument(s) for InCharge primitive '$callName'"
	unless( @{ $values } );

    if ( $type eq "S" ) {	# string
	return pack( "N/a*", shift @{ $values } );

    } elsif ( $type eq "." ) {	# char
	return shift @{ $values };

    } elsif ( $type eq "I" ) {	# signed 32bit integer
	return pack_i32s( shift @{ $values } );

    } elsif ( $type eq "i" ) {	# unsigned 32bit integer
	return pack_i32u( shift @{ $values } );

    } elsif ( $type eq "L" ) {	# signed 64bit integer
	return pack_i64s( shift @{ $values } );

    } elsif ( $type eq "l" ) {	# unsigned 64bit integer
	return pack_i64u( shift @{ $values } );

    } elsif ( $type eq "W" ) {	# signed 16bit integer
	return pack_i16s( shift @{ $values } );

    } elsif ( $type eq "w" ) {	# unsigned 16bit integer
	return pack_i16u( shift @{ $values } );

    } elsif ( $type eq "B" ) {	# boolean
	return pack_uchar( shift @{ $values } );

    } elsif ( $type eq "F" ) {	# float
	return pack_float32( shift @{ $values } );

    } elsif ( $type eq "D" ) {  # double        
	return pack_float64( shift @{ $values } );

    } elsif ( $type eq "@" ) {	# anyval array
	return encodeValues( $sock, $callName, "[*", $values );

    } elsif ( $type eq "#" or $type eq "*" ) {	# 'any'

	# This is a reference to a 2 element array, containing
	# type and value.
	#
	# This allows calls to primitives using syntaxes like..
	#
	#   InCharge::remote::invoke(
	#   $sock, "Router", "Fred", "getThing",
	#	[ [ 3, 632 ], [ "STRING", "Hello" ] ]
	#   );

	my $v = shift @{ $values };
	throw "[6] Reference to 2-element array expected for argument to ".
					    "InCharge primitive '$callName'"
	    unless (ref($v) eq "ARRAY" and $#{$v} == 1);
	my ( $type, $value ) = @{ $v };
	my $t = $data_types{$type};
	if (defined $t) { $type = $t; };
	my $itype = $typeCodeTable{ $type };
	throw "[6] Unknown argument (internal type '$type') for ".
					    "InCharge primitive '$callName'"
	    unless (defined $itype);
	if ($type == 50) { $type = 30; }
	if ($type == 51) { $type = 31; }
	return encodeValues( $sock, $callName, "I$itype->[0]", [ $type, $value ] );

    } elsif ( $type eq "O" ) {	# object (class is optional)
	my ( $class, $instance ) = _getObject( $sock, $values, 0 );
	return	encodeValue( $sock, $callName, "S", [$class]) .
	    encodeValue( $sock, $callName, "S", [$instance]);

    } elsif ( $type eq "J" ) {	# object (insist on class being specified)
	my ( $class, $instance ) = _getObject( $sock, $values, 1 );
	return	encodeValue( $sock, $callName, "S", [$class]) .
	    encodeValue( $sock, $callName, "S", [$instance]);

    } else {		# others - including compounds
	my $xtype = $compoundTypeTable{ $type };
	throw "[6] Unknown argument type '$type' for ".
					    "InCharge primitive '$callName'"
	    unless (defined $xtype);
	return encodeValues( $sock, $callName, $xtype, $values);
    }
}

#--------------------------------------------------------------------------
# $results = recvValues( $sock, $callname, $rtntypes )
#
# Reads data from the socket connection with the server, and converts it into
# a list of perl data types as directed by the $rtnTypes string.  This is
# logically the reverse of encodeValues except that it does real network
# accesses as part of it's logic.
#--------------------------------------------------------------------------

sub recvValues ($$$) {
    my ( $sock, $callName, $rtnTypes ) = @_;

    # Split the rtnTypes string into an array of characters for easy iteration
    my @rtnTypes = split( //, $rtnTypes );

    # Iterate over the specified return types, collecting the data from the
    # socket connection and decoding into perl variables.  We squirrel the
    # results away in the @rtn array as we go.
    
    my @rtn = ( );
    while ( @rtnTypes ) {
	my $rtnType = shift @rtnTypes;

	# If it's an array --

	if ( $rtnType eq "[" ) {
	    my $array = [ ];
	    my $type = shift @rtnTypes;

	    # how many values in the array?
	    my $n = recvValue( $sock, $callName, "I" );
	    # get them all and store.
	    for (my $i = 0; $i < $n; $i ++ ) {
		my @val = recvValue( $sock, $callName, $type );
		push @{$array}, @val;
	    }
	    push @rtn, $array;

	# If it's not an array --

	} else {
	    my @val = recvValue( $sock, $callName, $rtnType );
	    push @rtn, @val;
	}
    }

    # Return what we've collected to our caller

    return @rtn;
}

#--------------------------------------------------------------------------
# Reads a single value from the socket and decodes it appropriately. This
# is the main "work horse" for "recvValues" (plural) above.

sub recvValue ($$$) {
    my ( $sock, $callName, $type ) = @_;

    if ( $type eq "S" ) {	# string
	my $len = recvValue( $sock, $callName, "I" );
	return readSock( $sock, $callName, $len );

    } elsif ( $type eq "I" or $type eq "!" ) {	# signed 32bit integer
	return unpack_i32s( readSock( $sock, $callName, 4 ) );

    } elsif ( $type eq "i" ) {	# unsigned 32bit integer
	return unpack_i32u( readSock( $sock, $callName, 4 ) );

    } elsif ( $type eq "L" ) {	# signed 64bit integer
	return unpack_i64s( readSock( $sock, $callName, 8 ) );

    } elsif ( $type eq "l" ) {	# unsigned 64bit integer
	return unpack_i64u( readSock( $sock, $callName, 8 ) );

    } elsif ( $type eq "W" ) {	# signed 16bit integer
	return unpack_i16s( readSock( $sock, $callName, 2 ) );

    } elsif ( $type eq "w" ) {	# unsigned 16bit integer
	return unpack_i16u( readSock( $sock, $callName, 2 ) );

    } elsif ( $type eq "." ) {	# char
	return readSock( $sock, $callName, 1 );

    } elsif ( $type eq "B" ) {	# boolean
	return unpack_uchar( readSock( $sock, $callName, 1 ) );

    } elsif ( $type eq "F" ) {	# float		-- !!
	return unpack_float32( readSock( $sock, $callName, 4 ) );

    } elsif ( $type eq "D" ) {	# double	-- !!
	return unpack_float64( readSock( $sock, $callName, 8 ) );

    } elsif ( $type eq "V" ) {	# void
	return undef;

    } elsif ( $type eq "O" or $type eq "J" ) {	# object
	my @obj = recvValues( $sock, $callName, "SS" );
	if ( $obj[0] ne "" or $obj[1] ne "" ) {
	    return join( "::", @obj );
	} else {
	    return "";
	}

    } elsif ( $type eq "*" ) {

	# 'any' - the data type is specified by a integer code that precedes
	# the data in the incoming stream.
	my $type = recvValue( $sock, $callName, "I" );

	# if the user called a *_t primitive as *_T then we force a return of
	# type 51 (anyType with type codes embedded in nested structures) in
	# place of 31 (a "pure" anyType).
	if ( $addTypesToAnyvalArrays and ($type == 30)) { $type = 50; }
	if ( $addTypesToAnyvalArrays and ($type == 31)) { $type = 51; }
	my $xtype = $typeCodeTable{ $type };
	throw "[9] Cant decode data type $type in return for ".
					    "InCharge primitive '$callName'"
	    unless (defined $xtype);
	return recvValues( $sock, $callName, $xtype->[0] );

    } elsif ( $type eq "#" ) {
	# 'any with type' - like "any" (above) but we also pass the type code
	# back along with the value.
	my $type = recvValue( $sock, $callName, "I" );
	# see comment about type 51, above.
	my $org_type = $type;
	if ( $addTypesToAnyvalArrays and ($type == 30)) { $type = 50; }
	if ( $addTypesToAnyvalArrays and ($type == 31)) { $type = 51; }
	my $xtype = $typeCodeTable{ $type };
	throw "[9] Cant decode data type $type in return for ".
					    "InCharge primitive '$callName'"
	    unless (defined $xtype);
	my @values = recvValues( $sock, $callName, $xtype->[0] );
	unshift @values, $org_type;
	return [ @values ];

    } else {		# others - including compounds
	my $xtype = $compoundTypeTable{ $type };
	throw "[9] Unknown return type '$type' for ".
					    "InCharge primitive '$callName'"
	    unless (defined $xtype);
	if ( $xtype =~ m{^:(.*)} ) {
	    return [ recvValues( $sock, $callName, $1 ) ];
	} else {
	    return recvValues( $sock, $callName, $xtype );
	}
    }
}

#----------------------------------------------------------------------
# Buffered read from a socket. We handle timeouts here.
#----------------------------------------------------------------------


sub buffered_read ($$$) {
    my ( $sock, $wantedlen, $timeout ) = @_;
    my $bufferLen;
  

    # sanity check
    die "Crazy WANTEDLEN in buffered_read: $wantedlen"
	if ( $wantedlen < 1 or $wantedlen > (32*1024));

    # get the current buffer content
    my $fileno = getFlowFileno($sock);

    my $buff = $read_buffer[$fileno];

    # set the empty buffer up if it doesnt exist
    unless ( defined $buff ) {
	$buff = "";
	$read_buffer[$fileno] = "";
    }

    # how much data was in the buffer, waiting for us?
    my $already_got = length( $buff );

    # if we already have enough - just give it back, and remove that part from
    # the buffer - leaving only what we havent called for yet.
    if ( $already_got >= $wantedlen ) {
	my $rtn = substr( $buff, 0, $wantedlen );
	$read_buffer[$fileno] = substr( $buff, $wantedlen );
	return $rtn;
    }

    # get some more data - we ask for more that we actually need so that we can
    # fill up the buffer once - thus reducing the number of system calls made
    # (and hence improving performance).  Loop round this bit until we have at
    # least as much as we wanted in the first place.
    while ( length( $buff ) < $wantedlen ) {

	# If a timeout has been requested, we use the unix-like "select"
	# statement to implement it by waiting for the socket to have
	# readable data.
		if( $NO_FLOW){

	if (defined($timeout) and $timeout != -1) {
	    my ($rin, $rout, $eout) = ("","","");
	    vec($rin, $fileno, 1) = 1;
	    my $nfound = select($rout=$rin, undef, $eout=$rin, $timeout);

			    if ( $nfound < 1 ) {
					$broken[$fileno] = "[14] Timeout";
					throw $broken[$fileno];
			    }

			}

		}
		else{
		    if (defined($timeout) and $timeout != -1) 
		    {
                       my $nfound = $sock->flowReadableNow($timeout);

	    if ( $nfound < 1 ) {
		$broken[$fileno] = "[14] Timeout";
		throw $broken[$fileno];
	    }
	}

		}


	# get as much data as we can.
	my $collected = undef;
	
	if( $NO_FLOW){

		$collected = sysread( $sock, $buff, 1024, length( $buff ) );
		
	}
	else {

        $bufferLen=length( $buff );

		$bufferLen = 1024 if ($bufferLen<=0);
		
		my $buffTmp=" " x $bufferLen;
		
		$collected = $sock->flowRead($buffTmp,$bufferLen);
		
        $buff= $buff.substr( $buffTmp, 0, $collected );
	       							        
    }	        

	if (!defined($collected) or $collected < 1) {

	    # if the read failed for an IO error, we save the message in the
	    # $broken[] array so that we never try the connection again.
	    # A reconnect is required.
	    $broken[$fileno] = "[13] I/O Error";

	    # raise the error.
	    throw $broken[$fileno];
	}
    }

    # Now cut off the chunk we need and keep the rest for later.

    my $rtn = substr( $buff, 0, $wantedlen );
    $read_buffer[$fileno] = substr( $buff, $wantedlen );

    return $rtn;
}

#--------------------------------------------------------------------
# The basic easy-to-use version of the above call.
#
# Return an empty string if the no characters are needed
#
#--------------------------------------------------------------------

sub readSock ($$$) {
    my ( $sock, $callName, $wantedlen ) = @_;

    return "" if ($wantedlen == 0);
    my $buff = "";
    my $fileno  = getFlowFileno($sock);
    my $in = $inbuff[$fileno];
    my $timeout = $timeout[$fileno];

    if ( $broken[$fileno] ) {
	throw $broken[$fileno];
    }

    if ( defined($in) ) {
	$buff = substr( $in, 0, $wantedlen );
	$inbuff[$fileno] = substr( $in, $wantedlen );
    } else {
	$buff = buffered_read( $sock, $wantedlen, $timeout );
    }

    $rxbuff[$fileno] .= $buff;
    return $buff;
}


1;

#### eof ####			    vim:ts=8:sw=4:sts=4:tw=79:fo=tcqrnol1:noet:
