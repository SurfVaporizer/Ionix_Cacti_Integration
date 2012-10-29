#+ unix.pm - InCHarge Authorization support ftns for UNIX
#
# Copyright (c) 2003 System Management ARTS (SMARTS)
# All Rights Reserved.
#
# SMARTS provides this program 'as is' for educational and illustrative
# purposes only, without warranty or support.
#
# RCS $Id: //depot/smarts/dmt/rel/7.2/perlApi/perl/unix.pm#2 $
# $Source: /src/MASTER/smarts/perlApi/perl/unix.pm,v $
#

# This package is used internally by the InCharge:session module to
# obtain details of the user name and password to pass to the domain
# manager. It is not intended for direct use by user scripts.

package InCharge::auth::unix;

use Exporter;
@ISA = qw( Exporter );
$VERSION = "2.01";
@EXPORT = qw( open_chat send_chat readln_chat close_chat canask username );

use IO::Handle;
use IPC::Open2;
autoflush STDERR 1;
autoflush STDOUT 1;
autoflush STDIN 1;


my $pid;

sub close_chat {
    if($pid){
        close(RPIPE); close(WPIPE);
        kill("SIGKILL", $pid);
        waitpid($pid, 0);
        $pid = 0;
    }
}

sub send_chat {
    foreach ( @_ ) {
	print WPIPE $_;
    }
    WPIPE->flush();
}

sub readln_chat {
    return <RPIPE>;
}

sub open_chat {
    my ( $program ) = @_;
    undef($ENV{SM_REMAP_PROG});
    undef($ENV{SM_PREPEND_ARGS});
    $pid = open2( RPIPE, WPIPE, $program );
}

sub canask {
    return ( -t STDIN && -t STDOUT ) ? 1 : 0;
}

sub username {
    my $oslogin = eval{ (getpwuid( $< ))[0]; };
    $oslogin = getlogin() unless (defined $oslogin);
    return $oslogin;
}

1;
