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

use Moose;
use Carp;
use namespace::autoclean;
use Catalyst::Exception qw/throw/;

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

  %args = $self->_decorate_query(%args);
  
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

  %args = $self->_decorate_query(%args);

  my $result = $self->_es->count(%args);
  return $result->{count};
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

=head2 get_trackdbs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
                  - index - Scalar, elasticsearch index with trackDB JSON docs
                  - type  - Scalar, the ES type of the trackDB JSON docs
  Example     : my $docs = $model->get_trackdbs();
  Description : Search over the trackDB docs using a Search::Elasticsearch compatible query arg,
                should be equivalent to search_trackhubs but implemented with the scan&scroll API,
                so presumably faster. 
  Returntype  : ListRef - the Search::Elasticsearch compatible list of results
  Exceptions  : None
  Caller      : Registry::Controller::API::Registration
  Status      : Stable

=cut

sub get_trackdbs {
  my ($self, %args) = @_;

  # default: return all documents
  $args{query} = { match_all => {} }
    unless exists $args{query};

  %args = $self->_decorate_query(%args);

  # use scan & scroll API
  # Note that this is not compatible with ES6 and the Perl client library
  # Maybe it's fixed by the time you read this?
  
  # see https://metacpan.org/pod/Search::Elasticsearch::Scroll
  # use scan search type to disable sorting for efficient scrolling
  # $args{search_type} = 'scan';
  # my $scroll = $self->_es->scroll_helper(%args);
  
  # my @trackdbs;
  # while (my $trackdb = $scroll->next) {
  #   $trackdb->{_source}{_id} = $trackdb->{_id};
  #   push @trackdbs, $trackdb->{_source};
  # }

  my $trackdbs = $self->pager(\%args, sub { 
    my $result = shift;
    $result->{_source}{_id} = $result->{_id};
    return $result;
  });
  
  return $trackdbs;
}



=head2 count_existing_hubs

  Arg[1]  : String - User name
  Arg[2]  : String - Hub name
  Arg[3]  : String - Assembly accession, e.g. GCA00301030
  Description: Counts the number of hubs which match the supplied user details
  Returntype: Integer - number of hubs matching constraints

=cut

sub count_existing_hubs {
  my ($self, $user, $hub, $assembly_acc) = @_;

  my $query = $self->_existing_hub_query($user,$hub,$assembly_acc);
  return $self->count_trackhubs(query => $query);
}


=head2 get_existing_hubs

  Arg[1]  : String - User name
  Arg[2]  : String - Hub name
  Arg[3]  : String - Assembly accession, e.g. GCA00301030
  Description: Searches for matching hubs, and returns them
  Returntype: Listref - A list of elasticsearch results from the query

=cut

sub get_existing_hubs {
  my ($self, $user, $hub, $assembly_acc) = @_;

  my $query = $self->_existing_hub_query($user,$hub,$assembly_acc);
  my $result = $self->search_trackhubs(query => $query);
  if ($result->{hits}{total} == 0) {
    return [];
  }
  return $result->{hits}{hits};
}

=head2 _existing_hub_query

  Arg[1]  : String - User name
  Arg[2]  : String - Hub name
  Arg[3]  : String - Assembly accession, e.g. GCA00301030
  Description: Generates an ES6-compatible query to retrieve a hub for a named user
  Returntype: Hashref - formatted for Search::Elasticsearch

=cut

sub _existing_hub_query {
  my ($self, $user, $hub, $assembly_acc) = @_;

  my $query = {
    bool => {
      must => [
        { term => { owner => $user } },
        { term => { 'hub.name' => $hub } },
        { term => { 'assembly.accession' => $assembly_acc } }
      ]
    }
  };

  return $query;
}

sub get_hub_by_url {
  my ($self, $url) = @_;

  my $query = {
    bool => {
      must => [
        { term => { 'hub.url' => $url } }
      ]
    }
  };

  my $result = $self->search_trackhubs(query => $query);
  if ($result->{hits}{total} == 0) {
    return [];
  }
  return $result->{hits}{hits};
}

sub delete_hub_by_id {
  my ($self, $id) = @_;

  my $config = Registry->config()->{'Model::Search'};
 
  $self->delete(
    index => $config->{trackhub}{index},
    type => $config->{trackhub}{type},
    id => $id
  );
}

sub refresh_trackhub_index {
  my ($self) = @_;
  my $config = Registry->config()->{'Model::Search'};
  $self->indices->refresh(index => $config->{trackhub}{index})
}

sub create_trackdb {
  my ($self, $doc) = @_;
  my $config = Registry->config()->{'Model::Search'};

  my $response = $self->index(
    index   => $config->{trackhub}{index},
    type    => $config->{trackhub}{type},
    body    => $doc
  );

  my $new_id = $response->{_id};
  return $new_id
}



=head2 pager
  Arg[1]      : Hashref - containing query elements appropriate to Search::Elasticsearch
                body => { query => $query }, index => $index_name, type => $type
  Arg[2]      : Callback - code to post-process each of the documents in the result
  Examples    : my $result_list = $model->pager({query => { match => { ... } }, });
  Description : Fetches all the results for the query and buffers any paging that is required
  Returntype  : ListRef - A list of all the results for a large query

=cut

sub pager {
  my ($self, $query, $callback) = @_;

  my $from = 0;
  my $total_expected = -1;
  my @result_buffer = ();

  until (scalar @result_buffer == $total_expected) {

    $query->{size} ||= 10000; # Get the biggest chunks possible (restricted server-side)
    $from = scalar @result_buffer;
    $query->{from} = $from;

    my $result = $self->_es->search($query);
    if ($result->{timed_out}) {
      throw('Backend time out. Incomplete result obtained');
    }

    $total_expected = $result->{hits}{total} if $total_expected == -1;

    my $hits = $result->{hits}{hits};
    while (my $hit = shift @$hits) {
      if ($callback) {
        $hit = $callback->($hit);
      }
      push @result_buffer,$hit;
    }
    
  }

  return \@result_buffer;
}

sub _decorate_query {
  my ($self, %args) = @_;

  my $config = Registry->config()->{'Model::Search'};
  $args{index} = $config->{trackhub}{index};
  $args{type}  = $config->{trackhub}{type};

  # Search::Elasticsearch expects the query and any aggregations to be in the body
  # of the request.
  $args{body} = { query => $args{query} };
  delete $args{query};

  # homologate allowed aggregation names
  if (exists $args{aggs}) {
    $args{aggregations} = $args{aggs};
    delete $args{aggs};
  }

  if (exists $args{aggregations}) {
    $args{body}{aggs} = $args{aggregations};
    delete $args{aggregations};
  }
  return %args;
}

__PACKAGE__->meta->make_immutable;
1;
