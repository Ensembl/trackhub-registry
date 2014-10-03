package ElasticSearchDemo::Model::ElasticSearch;

#
# Meant to provide conventient methods to support the REST API
# by using the elasticsearch catalyst model API built around the 
# official Search::Elasticsearch 
#
# These extra functionalities are appropriately put in an app specific
# model, considering Catalyst::Model::ElasticSearch is meant to be a 
# minimalistic wrapper around the official Search::Elasticsearch API
#
use Moose;
use namespace::autoclean;
extends 'Catalyst::Model::ElasticSearch';

sub get_all_docs {
  my ($self, $index, $type) = @_;

  return $self->_es->search(index => $index,
			    type  => $type,
			    body  => { query => { match_all => {} } });
}

__PACKAGE__->meta->make_immutable;
1;
