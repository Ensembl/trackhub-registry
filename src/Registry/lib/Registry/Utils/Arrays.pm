=head1 LICENSE

Copyright [2015-2023] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

Please email comments or questions to the Trackhub Registry help desk
at C<< <http://www.trackhubregistry.org/help> >>

=head1 NAME

Registry::Utils::Array - Array utilities

=head1 SYNOPSIS

my @no_duplicates = remove_duplicates([1,2,1,1,2,4,6]);

my $no_duplicates2 = [1,2,3,4,5,6,7];
my ($union, $isect, $diff) union_intersection_difference(\@no_duplicates, $no_duplicates2);

=head1 DESCRIPTION

Provides useful functions to work with arrays, like extracting unique elements
from a list and determine the union/intersection/difference between two (unique)
lists.


=cut

package Registry::Utils::Arrays;


# A module to provide array utilities specified in
# the Perl CookBook book

use strict;
our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS, $VERSION);

use Exporter;
$VERSION = 1.00;
@ISA = qw( Exporter );

@EXPORT = qw();
@EXPORT_OK = qw( remove_duplicates union_intersection_difference );
%EXPORT_TAGS = ();

=head1 METHODS

=head2 remove_duplicates

  Arg [1]     : ArrayRef - reference to a list with duplicates.
  Example     : my @no_duplicates = remove_duplicates([1,2,1,1,2,4,6]);
  Description : Remove duplicates from a list
  Returntype  : A list with the duplicates removed
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

#
# Recipe 4.6 Perl Cookbook
# Extracting Unique Elements from a List
# 
# Parameters: a reference to an array
#
# NOTE
# 
# Could also use Lists::MoreUtils::uniq
#
sub remove_duplicates {
    my $a = shift;
    my %seen = ();
    return grep { ! $seen{$_} ++ } @$a;
}

=head2 union_intersection_difference

  Arg [1]     : ArrayRef - list with no duplicates
  Arg [2]     : ArrayRef - list with no duplicates
  Example     : my ($union, $isect, $diff) union_intersection_difference([1,2,3,4,5,6], [4,5,6,7];
  Description : Return the union/intersection/difference between two lists, assume the
                lists have no duplicates (so they in effect represents sets).
  Returntype  : (ArrayRef, ArrayRef, ArrayRef) <- (Union, Intersection, Difference)
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

#
# Recipe 4.8 Perl Cookbook
# Computing Union, Intersection, or Difference of Unique Lists
# 
# WARN
# 
# Assume there are not duplicates
#
# Parameters: two references to arrays 
#
sub union_intersection_difference {
    my ($a, $b) = @_;

    my (@union, @isect, @diff);
    my %count = ();
    foreach my $e (@$a, @$b) { $count{$e}++ }

    foreach my $e (keys %count) {
	push(@union, $e);
	if ($count{$e} == 2) {
	    push @isect, $e;
	} else {
	    push @diff, $e;
	}
    }
    return (\@union, \@isect, \@diff);
}

1;
