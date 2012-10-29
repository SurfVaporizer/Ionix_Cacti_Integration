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
# RCS $Id: //depot/smarts/dmt/rel/7.2/integ-accessor/perl/ParamGroup.pm#4 $
#
# ---------------------------------------------------------------------
package InCharge::ParamGroup;

=head1 NAME

    InCharge::ParamGroup - Support for manipulation of monitored
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

@EXPORT_OK = qw(find insert remove);


sub new {
  my ($class,$paramHash) = @_;
  my (%objects);
  my (%self);
  my (%empty);
  $paramHash = %empty unless defined($paramHash);
  $self{"parameters"} = $paramHash;
  $self{"objects"} = \%objects;
  bless \%self, $class;
}


sub insert {
  my ($self,$object) = @_;
  $self->{"objects"}->{$object->{instName}} = $object;
}

sub remove {
  my ($self,$object) = @_;
  delete($self->{"objects"}->{$object});
}

sub objects {
  my ($self) = @_;
  return values %{$self->{"objects"}};
}
