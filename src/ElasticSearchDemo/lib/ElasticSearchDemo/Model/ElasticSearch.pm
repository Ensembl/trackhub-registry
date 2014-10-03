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

#
# Get documents according to a given query
#
# Param is query parameters, default: return all docs
#
sub query {
  my ($self, %args) = @_;
  
  $args{index} ||= 'test';
  $args{type} ||= 'trackhub';
  $args{query} = { match_all => {} }
    unless exists $args{query};
  $args{body} = { query => $args{query} };
  delete $args{query};

  return $self->_es->search(%args);
}

__PACKAGE__->meta->make_immutable;
1;
