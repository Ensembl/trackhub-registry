package ElasticSearchDemo::Model::ElasticSearch;

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
