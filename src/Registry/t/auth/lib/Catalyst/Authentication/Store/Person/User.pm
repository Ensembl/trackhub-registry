=head1 LICENSE

Copyright [2015-2017] EMBL-European Bioinformatics Institute

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
