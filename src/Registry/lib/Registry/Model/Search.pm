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

=head1 CONTACT

Please email comments or questions to the Trackhub Registry help desk
at C<< <http://www.trackhubregistry.org/help> >>

=head1 NAME

Registry::Model::Search

=head1 SYNOPSIS

my $model = Registry::Model::Search->new();

# Empty search, get all documents
my $docs = $model->search_trckhubs();
print scalar @{$docs->{hits}{hits}}?"You've got hits!\n":"No hits.\n";

=head1 DESCRIPTION

Catalyst model Meant to provide conventient methods tailored for trub hubs to support 
the REST API. It uses the elasticsearch catalyst model API built around the official 
Search::Elasticsearch. 

These extra functionalities are appropriately put in an app specific model, considering 
Catalyst::Model::ElasticSearch is meant to be a minimalistic wrapper around the official 
Search::Elasticsearch API.

=head1 BUGS

next_trackdb_id seems to be working not as reliably as expected, disable its use in
controller.

=cut

package Registry::Model::Search;

use Carp;
use Moose;
use namespace::autoclean;
extends 'Catalyst::Model::ElasticSearch';

=head1 METHODS

=head2 search_trackhubs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
                  - index - Scalar, elasticsearch index with trackDB JSON docs
                  - type  - Scalar, the ES type of the trackDB JSON docs
  Example     : my $docs = $model->search_trackhubs(query = > { match_all = {} });
  Description : Search over the trackDB docs using a Search::Elasticsearch compatible query arg
  Returntype  : HashRef - the Search::Elasticsearch compatible result
  Exceptions  : None
  Caller      : General
  Status      : Stable


=cut

sub search_trackhubs {
  my ($self, %args) = @_;

  # default: return all documents
  $args{query} = { match_all => {} }
    unless exists $args{query};

  # add required (by Search::Elasticsearch)
  # index and type parameter
  my $config = Registry->config()->{'Model::Search'};
  $args{index} = $config->{trackhub}{index};
  $args{type}  = $config->{trackhub}{type};

  # this is what Search::Elasticsearch expect 
  $args{body} = { query => $args{query} };
  delete $args{query};

  return $self->_es->search(%args);
}

=head2 count_trackhubs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
                  - index - Scalar, elasticsearch index with trackDB JSON docs
                  - type  - Scalar, the ES type of the trackDB JSON docs
  Example     : my $hits = $model->count_trackhubs(query = > { match_all = {} });
  Description : Count the number of trackDB docs matching a given Search::Elasticsearch compatible query arg
  Returntype  : Scalar - the hits count
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub count_trackhubs {
  my ($self, %args) = @_;

  # default: return all documents
  $args{query} = { match_all => {} }
    unless exists $args{query};

  # add required (by Search::Elasticsearch)
  # index and type parameter
  my $config = Registry->config()->{'Model::Search'};
  $args{index} = $config->{trackhub}{index};
  $args{type}  = $config->{trackhub}{type};

  # this is what Search::Elasticsearch expect 
  $args{body} = { query => $args{query} };
  delete $args{query};

  return $self->_es->count(%args);
}

=head2 get_trackhub_by_id

  Arg[1]      : Scalar - ES trackDB doc ID (required)
  Arg[2]      : Bool - whether to get the original ES document (the original doc with ES decorated metadata) 
                instead of just the source
  Example     : my $trackDB = $model->get_trackhub_by_id(1);
  Description : Get the trackDB doc with the given (ES) id
  Returntype  : HashRef - a Search::Elasticsearch compatible representation of the ES doc
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub get_trackhub_by_id {
  my ($self, $id, $orig) = @_;

  croak "Missing required id parameter"
    unless defined $id;

  my $config = Registry->config()->{'Model::Search'};
  return $self->_es->get_source(index => $config->{trackhub}{index}, # add required (by Search::Elasticsearch)
                                type  => $config->{trackhub}{type},  # index and type parameter 
                                id    => $id) unless $orig;

  return $self->_es->get(index => $config->{trackhub}{index},           
                         type  => $config->{trackhub}{type},  
                         id    => $id);
  
}

=head2 next_trackdb_id

  Arg[1]      : None
  Example     : my $nextid = $model->next_trackdb_id;
  Description : Return the next available ES ID, to be used when inserting a new trackDB
                doc created when submitting a hub
  Returntype  : Scalar - an Elasticsearch ID
  Exceptions  : None
  Caller      : Registry::Controller::API::Registration
  Status      : Stable

=cut

sub next_trackdb_id {
  my ($self) = @_;

  my $config = Registry->config()->{'Model::Search'};
  # my %args = 
  #   (
  #    index => $config->{trackhub}{index},
  #    type  => $config->{trackhub}{type},
  #    size  => 1,
  #    body  => {
  # 	       fields => [ '_id' ],
  # 	       query  => { match_all => {} },
  # 	       # sorting on the _id field doesn't work, it does on the _uid one.
  # 	       # http://stackoverflow.com/questions/29667212/whats-the-different-between-id-and-uid-in-elasticsearch
  # 	       # _id and _uid are not the same thing.
  # 	       # the internal _uid field is the unique identifier of a document within an index and is composed of the 
  # 	       # type and the id (meaning that different types can have the same id and still maintain uniqueness).
  # 	       # The _uid field is automatically used when _type is not indexed to perform type based filtering, and does 
  # 	       # not require the _id to be indexed.
  # 	       # https://www.elastic.co/guide/en/elasticsearch/reference/1.3/mapping-uid-field.html
  # 	       sort   => [ { _uid => { order => 'desc' } } ]
  # 	      }
  #   );
  # return $self->search(%args)->{hits}{hits}[0]{_id}+1;

  my %args =
    (
     index => $config->{trackhub}{index},
     type  => $config->{trackhub}{type},
     body  => { query => { match_all => {} } },
     search_type => 'scan'
    );

  my $max_id = -1;
  my $scroll = $self->_es->scroll_helper(%args);
  while (my $trackdb = $scroll->next) {
    $max_id = $trackdb->{_id} if $max_id < $trackdb->{_id};
  }

  return $max_id>0?$max_id+1:1;
}

=head2 get_trackdbs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
                  - index - Scalar, elasticsearch index with trackDB JSON docs
                  - type  - Scalar, the ES type of the trackDB JSON docs
  Example     : my $docs = $model->get_trackdbs();
  Description : Search over the trackDB docs using a Search::Elasticsearch compatible query arg,
                should be equivalent to search_trackhubs but implemented with the scan&scroll API,
                so presumably faster. 
  Returntype  : HashRef - the Search::Elasticsearch compatible result
  Exceptions  : None
  Caller      : Registry::Controller::API::Registration
  Status      : Stable

=cut

sub get_trackdbs {
  my ($self, %args) = @_;

  # default: return all documents
  $args{query} = { match_all => {} }
    unless exists $args{query};

  my $config = Registry->config()->{'Model::Search'};
  $args{index} = $config->{trackhub}{index};
  $args{type}  = $config->{trackhub}{type};

  # this is what Search::Elasticsearch expect 
  $args{body} = { query => $args{query} };
  delete $args{query};

  # use scan & scroll API
  # see https://metacpan.org/pod/Search::Elasticsearch::Scroll
  # use scan search type to disable sorting for efficient scrolling
  $args{search_type} = 'scan';
  my $scroll = $self->_es->scroll_helper(%args);
  
  my @trackdbs;
  while (my $trackdb = $scroll->next) {
    $trackdb->{_source}{_id} = $trackdb->{_id};
    push @trackdbs, $trackdb->{_source};
  }

  # my @trackdbs;
  # $args{size} = 10000;
  # foreach my $doc (@{$self->_es->search(%args)->{hits}{hits}}) {
  #   $doc->{_source}{_id} = $doc->{_id};
  #   push @trackdbs, $doc->{_source};
  # }
  
  return \@trackdbs;
}

__PACKAGE__->meta->make_immutable;
1;
