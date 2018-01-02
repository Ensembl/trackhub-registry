=head1 LICENSE

Copyright [2015-2018] EMBL-European Bioinformatics Institute

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

package Data::SearchEngine::ElasticSearch::Query;

#
# extends Data::SearchEngine::Query to provide
# ElasticSearch specific attributes/methods,
# e.g. data type
#


use Moose;
extends 'Data::SearchEngine::Query';

has data_type => (
    traits => [qw(Digestable)],
    is => 'rw',
    isa => 'Str',
    predicate => 'has_datatype'
);

has aggregations => (
    traits => [qw(Digestable)],
    is => 'rw',
    isa => 'HashRef',
    predicate => 'has_aggregations'
);

no Moose;
__PACKAGE__->meta->make_immutable;
