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
