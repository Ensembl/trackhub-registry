package Catalyst::Authentication::Store::Person::User;

use strict;
use warnings;
use Moose 2.00;
extends 'Catalyst::Authentication::Store::ElasticSearch::User';

around load => sub {
  my $orig = shift;
  my $class = shift;
  return $class->$orig(@_);
};


1;
__END__
