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
# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-accessor/perl/ParamGroupSet.pm#5 $
#
# ---------------------------------------------------------------------
package InCharge::ParamGroupSet;

=head1 NAME

    InCharge::ParamGroupSet - Support for manipulation of monitored
    objects via grouping by parameter set values

=cut

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

our $VERSION = '1.3';

use vars qw(@ISA 
            @EXPORT_OK 
            $VERSION);

use Carp qw(croak carp);
use Exporter;

@ISA = ('Exporter');

@EXPORT_OK = qw(groups insert remove find groupByParameter);


sub new {
  my ($class,$monitoring,@args) = @_;
  my %self;
  my ($self) = bless \%self, $class;
  if (defined($monitoring) and $#args ) {
    $self->groupByParameter($monitoring,@args);
  }
  return $self;
}

sub groupByParameter {
  my ($self) = shift;
  my ($monitoring) = shift;
  my (%args) = @_;

  my ($obj);
  foreach $obj ( values %{$monitoring->{objects}} ) {
    my %objParams = %{$obj->{parameters}};
    my %usedValues;
    my $key = "";

    my ($param);
    foreach $param ( sort keys %args ) {
      my $value = $objParams{$param};
      if ( ! defined($value) ) {
        if ( defined(  $args{$param} ) ) {
          $value = $args{$param};
        } else {
          $key = "";
          last;
        }
      } 
      $key .= "::$value";
      $usedValues{$param} = $value;
    }
    if ($key) {
      my $paramGroup = $self->find($key);
      if (! defined( $paramGroup ) ) {
        $paramGroup = InCharge::ParamGroup->new( \%usedValues );
        $self->insert($key, $paramGroup);
      }
      $paramGroup->insert($obj);
    }
  }
  return $self;
}

sub insert {
  my ($self,$key,$value) = @_;
  $self->{$key} = $value;
}

sub groups {
  my ($self) = @_;
  return values %{$self};
}

sub remove {
  my ($self,$key) = @_;
  delete $self->{$key};
}

sub find {
  my ($self,$key) = @_;
  return $self->{$key};
}
