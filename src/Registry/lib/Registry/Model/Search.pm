package Registry::Model::Search;

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

use Registry;

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
  my $config = Registry->config()->{'Model::Search'};
  $args{index} = $config->{index};
  $args{type}  = $config->{type}{trackhub};

  # this is what Search::Elasticsearch expect 
  $args{body} = { query => $args{query} };
  delete $args{query};

  return $self->_es->search(%args);
}

#
# Count the documents matching a given query
#
sub count_trackhubs {
  my ($self, %args) = @_;

  # default: return all documents
  $args{query} = { match_all => {} }
    unless exists $args{query};

  # add required (by Search::Elasticsearch)
  # index and type parameter
  my $config = Registry->config()->{'Model::Search'};
  $args{index} = $config->{index};
  $args{type}  = $config->{type}{trackhub};

  # this is what Search::Elasticsearch expect 
  $args{body} = { query => $args{query} };
  delete $args{query};

  return $self->_es->count(%args);
}

#
# Return a document given its ID
#
# Params: 
# - id (required) - the ID of the document
# - orig - get the original document (content+metadata) instead of just its source (content)
#
sub get_trackhub_by_id {
  my ($self, $id, $orig) = @_;

  croak "Missing required id parameter"
    unless defined $id;

  my $config = Registry->config()->{'Model::Search'};
  return $self->_es->get_source(index => $config->{index},           # add required (by Search::Elasticsearch)
				type  => $config->{type}{trackhub},  # index and type parameter 
				id    => $id) unless $orig;

  return $self->_es->get(index => $config->{index},           
			 type  => $config->{type}{trackhub},  
			 id    => $id) unless $orig;
  
}

sub get_all_users {
  my $self = shift;

  my $config = Registry->config()->{'Model::Search'};
  
  # use scan & scroll API
  # see https://metacpan.org/pod/Search::Elasticsearch::Scroll
  my $scroll = $self->_es->scroll_helper(index => $config->{index},
					 type  => $config->{type}{user});
					 # body  => { query => {... some query ... }});
  my @users;
  while (my $user = $scroll->next) {
    push @users, $user->{_source};
  }
  return \@users;
}

sub get_latest_report {
  my $self = shift;

  my $config = Registry->config()->{'Model::Search'};
  my %args;
  $args{index} = $config->{index};
  $args{type}  = $config->{type}{report};
  $args{size} = 1;
  $args{body} = 
    {
     sort => [ 
	      { 
	       created => {
			   order => 'desc',
			   # would otherwise throw exception if there
			   # are documents missing the field,
			   # see http://stackoverflow.com/questions/17051709/no-mapping-found-for-field-in-order-to-sort-on-in-elasticsearch
			   ignore_unmapped => 'true' 
			  }
	      }
	     ]
    };
  
  return $self->search(%args)->{hits}{hits}[0];
}

__PACKAGE__->meta->make_immutable;
1;
