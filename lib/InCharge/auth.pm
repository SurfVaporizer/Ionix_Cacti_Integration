#+ auth.pm - InCharge Authorization support ftns
#
# Copyright (c) 2003 System Management ARTS (SMARTS)
# All Rights Reserved.
#
# SMARTS provides this program 'as is' for educational and illustrative
# purposes only, without warranty or support.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/perlApi/perl/auth.pm#6 $
# $Source: /src/MASTER/smarts/perlApi/perl/auth.pm,v $
#

# This package is used internally by the InCharge:session module to obtain
# details of the user name and password to pass to the domain manager. It is
# not intended for direct use by user scripts.

package InCharge::auth;

our $VERSION = '2.01';
use Config;
use Sys::Hostname;
use IO::Handle;
use InCharge::remote;

*throw = \&InCharge::remote::throw;

our $w32auth;

# login_matches() is used by the clientConnect.conf file scanning logic.  It is
# used to match the login name specified in the file against the actual OS
# login name. The special case of "*" wild card in the file is handled - it
# matches anything.

sub _login_matches ($$) {
    my ( $configured, $specified ) = @_;
    return 1 if ( $configured eq "*" );
    return 1 if ( $configured eq $specified );
    return 0;
}

# target_matches() is also used by the clientConnect.conf file scanning logic.
# This is used to match the domain name target. The special case of "~<BROKER>"
# matches anything other than "<BROKER>".

sub _target_matches ($$) {
    my ( $configured, $specified ) = @_;
    return 1 if ( $configured eq "*" );
    return 1 if ( $configured eq $specified );
    return 1 if ( $configured eq "<BROKER>" and $specified eq "dmbroker" );
    return 1 if ( $configured eq "~<BROKER>" and $specified ne "<BROKER>"
						and $specified ne "dmbroker" );
    return 0;
}

# Interact with the operator to obtain the login user name for a given domain.
# We display a question and read the reply - simple really!

sub _prompt_user ($) {
    require Term::ReadKey;
    my ( $domain ) = @_;
    eval{&Term::ReadKey::ReadMode(1);};
    return undef if ( $@ );
    print "User name for login to domain '$domain': ";
    STDOUT->flush();
    my $user;
    chomp( $user = (&Term::ReadKey::ReadLine(0)) );
    &Term::ReadKey::ReadMode(0);
    return $user;
}

# Interact with the operator to obtain a password. We turn "echo" mode off for
# the terminal as we go, so that the password cannot be seen on the screen as
# it is typed.

sub _prompt_password () {
    require Term::ReadKey;
    eval{&Term::ReadKey::ReadMode(2);};
    return undef if ( $@ );
    print "Password: ";
    STDOUT->flush();
    my $pass;
    chomp( $pass = (&Term::ReadKey::ReadLine(0)) );
    &Term::ReadKey::ReadMode(0);
    print "\n";
    return $pass;
}

# The interaction to use under "default" conditions - ie when the
# clientConnect.conf is missing.

sub _defaultInteraction($$) {
    my ( $domain, $istty ) = @_;

    if ($domain eq "<BROKER>") { return( "BrokerNonsecure", "Nonsecure" ); }
    if ((!$istty)) { return( undef, undef ); }

    my $incharge_user = _prompt_user( $domain );
    if (! defined $incharge_user) { return( undef, undef ); }
    my $password = _prompt_password();
    if (! defined $password) { return( undef, undef ); }
    return ( $incharge_user, $password );
}

# gets the user name and password from the clientConnect.conf file or a user
# interaction (as specified in the conf file).	If the file cant be found
# (because SM_HOME is specified or the file doesnt exist in the expected
# location) then a default interaction is used.

sub _sm_authority ($) {
    my ( $domain ) = @_;
    my $istty = ( -t STDIN ) ? 1 : 0;
    my $oslogin = username();

    # open and read the clientConnect.conf file
    my $path_sep = $Config{path_sep};
    my @path_dirs = split( /$path_sep/, $ENV{SM_WRITEABLE} );
    push @path_dirs, $ENV{SM_HOME};

    my $filename = undef;
    for my $dir ( @path_dirs ) {
	$dir =~ s/\\/\//g;
	if ( -r "$dir/conf/clientConnect.conf" ) {
	    $filename = "$dir/conf/clientConnect.conf";
	}
    }

    unless (defined $filename) {
	return _defaultInteraction($domain,$istty);
    }

    unless ( open( CCC, "< $filename" ) ) {
	throw("[18] Cant open file: $filename");
    }

    my $ccc = join( "", <CCC> );
    close(CCC);

    $ccc =~ s{\r}{}sg;	    # strip carriage returns
    $ccc =~ s{(#|//)(.*?)\n}{\n}sg; # strip comments
    $ccc =~ s{^\s*\n}{}sg;	# remove blank lines
    $ccc =~ s{\\\n}{}sg;	# remove escaped newlines
    $ccc =~ s{^\s*}{}mg;	# remove leading white space
    $ccc =~ s{\s*$}{}mg;	# remove trailing white space

    foreach ( split( /\n/, $ccc ) ) {
	next if ( m{<PROMPT>} and !$istty );

	my ( $login_user, $target, $incharge_user, $password ) =
	    split( /\s*:\s*/, $_ );
	if (
	    _login_matches( $login_user, $oslogin ) &&
	    _target_matches( $target, $domain )
	) {
	    if ( $incharge_user eq "<PROMPT>" ) {
		$incharge_user = _prompt_user( $domain );
		next if (!defined($incharge_user));
	    }

	    if ( $password eq "<PROMPT>" ) {
		$password = _prompt_password();
		next if (!defined($incharge_user));
	    }

	    if ( $incharge_user eq "<DEFAULT>" ) {
		return ( undef, undef );
	    } elsif ( $incharge_user eq "<USERNAME>" ) {
		return ( $oslogin, $password );
	    } else {
		return ( $incharge_user, $password );
	    }
	}
    }
    return ( undef, undef );
}

sub getCredentials($$) {
    my ( $program, $domain ) = @_;

    __init();

    if ( $program =~ m{[^A-Za-z0-9_\.-]} ) {
	throw( "[18] Program name contains invalid characters" );
    }

    if ( $program !~ m{\.} and ($Config{osname} eq "MSWin32" or $Config{osname} eq "cygwin") ) {
	$program .= ".exe";
    }

    # Look in SM_SITEMOD and SM_HOME for sm_authority (or configured
    # alternative) program binary.

    my $path_sep = $Config{path_sep};
    my @path_dirs = split( /$path_sep/, $ENV{SM_SITEMOD} );
    push @path_dirs, $ENV{SM_HOME};

    my $path = undef;
    for my $dir ( @path_dirs ) {
	$dir =~ s/\\/\//g;
        if ( -x "$dir/bin/system/$program" and $Config{osname} eq "MSWin32" and defined($ENV{"SM_PERL_BASE"})) {
            $path = "$dir/bin/system/$program";
        } elsif ( -x "$dir/bin/$program" ) {
            $path = "$dir/bin/$program";
        }
    }

    # Throw a magic string (caught elsewhere in this module) if we didnt find
    # our expected binary
    throw("PROG_NOT_FOUND\n" ) unless ( defined ($path) );

    open_chat( $path );

    my $x = chr(3);
    my $canask = canask();
    my $host = hostname();
    my $user = username();

    my $domain_key = ($domain eq "<BROKER>") ? "dmbroker" : $domain;
    my $tx = "credentials?${x}$host${x}$domain_key${x}$user${x}$canask".
							    "${x}0${x}0\n";
    send_chat( $tx );
    $reply = readln_chat();
    $reply =~ s{\r?\n$}{}s;
    my @reply = split( chr(3), $reply );

    if ( $reply[0] eq "credentials" ) {
	my ( $tag, $ic_user, $ic_password, $cookie, $interactive, $error )
								    = @reply;
	close_chat();
	return ( $ic_user, $ic_password, $cookie ) if ( $error eq "0" );
	throw( "[4] Cant get user credentials - error code: $error" );
    }

    if ( $reply[0] eq "prompt?" ) {
	my $ic_user = _prompt_user( $domain );
	my $ic_password = _prompt_password();
	my $tx = "prompt${x}$ic_user${x}$ic_password${x}0\n";
	send_chat( $tx );
	$reply = readln_chat();
	$reply =~ s{\r?\n$}{}s;
	@reply = split( chr(3), $reply );
	if ( $reply[0] eq "credentials" ) {
	    my ( $tag, $ic_user, $ic_password, $cookie, $interactive, $error )
								    = @reply;
	    close_chat();
	    return ( $ic_user, $ic_password, $cookie ) if ( $error eq "0" );
	    throw( "[4] Cant get user credentials - error code: $error" );
	}
    }

    close_chat();
    throw( "[2] Unexpected reply from authenticator" );
}

sub __init {

    # Unix + Windows can both use the same module
    eval "use InCharge::auth::unix;";

    throw( $@ ) if ( $@ );
}

sub getLoginAndPassword {
    my ( $domain ) = @_;

    __init();

    # Get the configured SM_AUTHORITY setting, and map old versions to the
    # new V6 logic.
    my $conf = $ENV{SM_AUTHORITY};
    $conf = "IDENTIFY=sm_authority,AUTHENTICATE=sm_authority"
        if ( $conf eq "<STD>" or $conf eq "" );
    $conf = "IDENTIFY=sm_authnone,AUTHENTICATE=sm_authnone"
	if ( $conf eq "<NONE>" );

    # Now rip the string apart to obtain the two program names.
    my %conf = ( );
    if ($conf =~ m{^\s*(\w+)\s*=\s*(.*?)\s*,\s*(\w+)\s*=\s*(.*?)\s*$}) {
	$conf{$1} = $2;
	$conf{$3} = $4;
    } else {
	throw( "[18] Invalid SM_AUTHORITY syntax" );
    }
    thow( "[18] 'IDENTIFY' option is missing from SM_AUTHORITY" )
	unless ( $conf{IDENTIFY} );

    # Use the configured utility to collect the credentials.
    my ( $user, $pass, $cookie ) =
	eval { getCredentials( $conf{IDENTIFY}, $domain ); };

    # If the "getCredentials" failed because the specified program doesnt
    # exist, and it was one of the standard ones - then use our built-in
    # logic. This leaves us backwards compatible with V4.x and V5.x
    # releases of InCharge.
    if ( $@ eq "PROG_NOT_FOUND\n" and $conf{IDENTIFY} eq "sm_authnone" ) {
	$user = undef;
	$pass = undef;
    } elsif ( $@ eq "PROG_NOT_FOUND\n" and $conf{IDENTIFY} eq "sm_authority" ) {
	( $user, $pass ) = _sm_authority( $domain );
    } elsif ( $@ =~ m{^\[\d+\]} ) {
	throw( $@ );
    } elsif ( $@ ) {
	throw( "[4] $@" );
    }

    $pass =~ s/^<E-0\.\d+>//;
    if ( $pass =~ m/^<E-/ ) {
	throw("[18] Password for user '$user' still encrypted\n"
	    ."HINT: Are SM_AUTHORITY, SM_HOME and/or SM_SITEMOD correctly configured?");
    }
    $user = undef if ($user eq "<DEFAULT>");
    $pass = undef if ($pass eq "<DEFAULT>");

    return ( $user, $pass );
}

1;

