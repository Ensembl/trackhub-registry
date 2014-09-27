package ElasticSearchDemo::Model::ElasticSearch;

use Moose;
use namespace::autoclean;
extends 'Catalyst::Model::ElasticSearch';

__PACKAGE__->meta->make_immutable;
1;
