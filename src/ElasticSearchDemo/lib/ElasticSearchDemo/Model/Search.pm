package ElasticSearchDemo::Model::Search;

#
# Meant to provide conventient methods to support the REST API
# by using the elasticsearch catalyst model API built around the 
# official Search::Elasticsearch 
#
# These extra functionalities are appropriately put in an app specific
# model, considering Catalyst::Model::ElasticSearch is meant to be a 
# minimalistic wrapper around the official Search::Elasticsearch API
#

use Carp;
use Moose;
use namespace::autoclean;
extends 'Catalyst::Model::ElasticSearch';

use ElasticSearchDemo;

#
# Get documents according to a given query
#
# Param is query, default: return all docs
#
sub search_trackhubs {
  my ($self, %args) = @_;

  # default: return all documents
  $args{query} = { match_all => {} }
    unless exists $args{query};

  # add required (by Search::Elasticsearch)
  # index and type parameter
  my $config = ElasticSearchDemo->config()->{'Model::Search'};
  $args{index} = $config->{index};
  $args{type}  = $config->{type};

  # this is what Search::Elasticsearch expect 
  $args{body} = { query => $args{query} };
  delete $args{query};

  return $self->_es->search(%args);
}

#
# Return a document given its ID
#
# Params (required): id
#
sub get_trackhub_by_id {
  my ($self, $id) = @_;

  croak "Missing required id parameter"
    unless defined $id;

  my $config = ElasticSearchDemo->config()->{'Model::Search'};
  return $self->_es->get_source(index => $config->{index}, # add required (by Search::Elasticsearch)
				type  => $config->{type},  # index and type parameter 
				id    => $id);
}

__PACKAGE__->meta->make_immutable;
1;
