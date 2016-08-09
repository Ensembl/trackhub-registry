=head1 LICENSE

Copyright [2015-2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

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
