package My::App::Model::Search;

use Moose;
use namespace::autoclean;
extends 'Catalyst::Model::Search::ElasticSearch';

__PACKAGE__->meta->make_immutable;
1;
