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
use Try::Tiny;
use POSIX;
use Catalyst::Exception qw/throw/;

extends 'Catalyst::Model::ElasticSearch';

=head1 METHODS

=head2 search_trackhubs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
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
  try {
    my $result = $self->_es->search(%args);
    return $result;
  } catch {
    Catalyst::Exception->throw("Backend query problem:\n $_");
  };
}

=head2 count_trackhubs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
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
    unless defined $id; # THIS IS NOT THE WAY TO RETURN ERRORS

  my $config = $self->schema->{trackhub};
  try {
    if ($orig) {
      return $self->get_source(
        index => $config->{index_name},
        type  => $config->{type},  # index and type parameter 
        id    => $id
      );
    } else {
      return $self->get(
        index => $config->{index_name},           
        type  => $config->{type},  
        id    => $id
      );
    }
  } catch {
    # Failed searches return no hits, but getting a document by ID can fail
    if (m/404/) {
      Catalyst::Exception->throw('Unable to get hub with id '.$id);
    } else {
      Catalyst::Exception->throw('Unexpected error: '.$_);
    }
  };
}

=head2 get_trackdbs

  Arg[1]      : Hash - hash of query parameters
                  - query - HashRef, the Search::Elasticsearch compatible query parameter
  Example     : my $docs = $model->get_trackdbs();
  Description : Search over the trackDB docs using a Search::Elasticsearch compatible query arg,
                should be equivalent to search_trackhubs but implemented with the scan&scroll API,
                so size uncapped.
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

  # use scan & scroll API from ES client 5 with v6 scroll API component added
  # Maybe it's tidied up into a single install by the time you read this?
  
  # see https://metacpan.org/pod/Search::Elasticsearch::Scroll

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
  Description: Counts the number of hubs (as distinct from trackDBs) which match the supplied user details
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
  Description: Searches for matching hubs, and returns the number of them.
               Semi-redundant with the general count methods
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

=head2 get_hub_by_url

  Arg[1]     : String - URL of original trackhub
  Description: Returns a list of hub documents
  Returntype : Listref - formatted for Search::Elasticsearch and extracted from search result

=cut


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


=head2 get_hubs_by_user_name

  Arg[1]      : String - username as registered by the user
  Description : Returns a list of hub documents
  Returntype  : Listref - formatted for Search::Elasticsearch and extracted from search result

=cut

sub get_hubs_by_user_name {
  my ($self, $user_name) = @_;

  my $query = {
    query => {
      term => {
        owner => $user_name
      }
    }
  };

  my $result = $self->search_trackhubs(%$query);
  if ($result->{hits}{total} == 0) {
    return [];
  }
  return $result->{hits}{hits};
}

=head2 delete_hub_by_id

  Arg[1]      : String - Elasticsearch document id
  Description : Deletes the requested document from the backend
  Returntype  : None

=cut

sub delete_hub_by_id {
  my ($self, $id) = @_;

  my $config = $self->schema->{trackhub};
 
  $self->delete(
    index => $config->{index_name},
    type => $config->{type},
    id => $id
  );
}

=head2 refresh_trackhub_index

  Description: Triggers a synchronisation event in the backend cluster so that recently
               inserted documents will appear in new searches. Otherwise they won't
               appear until the backend decides on its own to refresh
  Returntype : None

=cut

sub refresh_trackhub_index {
  my ($self) = @_;
  $self->indices->refresh(index => $self->schema->{trackhub}{index_name});
}


=head2 create_trackdb
  
  Arg[1]      : hashref structure representing a single trackDB entity
  Description : Submit a new document to be indexed
  Returntype  : String - the unique ID assigned to the new document

=cut

sub create_trackdb {
  my ($self, $doc) = @_;
  my $config = $self->schema->{trackhub};

  my $response = $self->index(
    index   => $config->{index_name},
    type    => $config->{type},
    body    => $doc
  );

  my $new_id = $response->{_id};
  return $new_id;
}


=head2 api_search
 
  Arg[1]      : String - free text query
  Arg[2]      : Int - page of paginated results
  Arg[3]      : Int - number of documents per page to return
  Arg[4]      : String - species name
  Arg[5]      : String - assembly name
  Arg[6]      : String - A INSDC assembly accession, GCA....
  Arg[7]      : String - Name of a track hub
  Arg[8]      : String - Type of track hub, e.g. proteomics or whatever
  Description : Search routine for API clients, no aggregations by default, 
                just a combination of search constraints
  Returntype : Listref of hits from the backend

=cut

# Search routine for API clients, no aggregations by default, just a combination of search constraints
sub api_search {
  my ($self, $user_query, $page, $per_page, $species, $assembly, $accession, $hub, $type) = @_;

  printf("query: %s page: %s per-page:%s species:%s assembly:%s hub:%s type:%s\n",$user_query, $page, $per_page, $species, $assembly, $hub, $type);

  my %query = (
    from => ($page-1) * $per_page,
    size => $per_page
  );

  my @extra_clauses;
  my @optional_clauses;
  if ($user_query ne '') { push @extra_clauses,{ match => $user_query } ; }
  push @extra_clauses, {public => "true" }; # present only 'public' hubs
  push @extra_clauses, { "species.scientific_name.lowercase" => lc $species } if $species;
  # if assembly is provided extend the search to both the name and synonyms to allow fetching

  # ENSCORESW-2039
  # put assembly parameter as query string, otherwise cannot find some assemblies
  # due to the way assembly.synonyms and assembly.name are (not) indexed in combination
  # with the use of a filter
  if ($assembly) {
    push @optional_clauses, { "assembly.name" => $assembly };
    push @optional_clauses, { "assembly.synonyms" => $assembly };
    push @optional_clauses, { "assembly.accession" => $assembly };
  }
  push @extra_clauses, { "assembly.accession" => $accession } if $accession;
  push @extra_clauses, { "hub.name" => $hub } if $hub;
  push @extra_clauses, { type => $type } if $type;

  foreach my $clause (@extra_clauses) {
    push @{ $query{query}{bool}{must} }, { term => $clause};
  }
  foreach my $clause (@optional_clauses) {
    push @{ $query{query}{bool}{should}}, { term => $clause};
  }
  if (@optional_clauses) {
    $query{query}{bool}{minimum_should_match} = 1;
  }

  my $response = $self->search_trackhubs(%query);
  $response = $self->clean_results($response);

  # Format for return to user
  my $hits = {
    total_entries => $response->{hits}{total},
    items => $response->{hits}{hits}
  };
  return $hits;
}

=head2 clean_results
  
  Arg[1]      : listref structure containing raw hits from backend
  Description : Cleans all the Elasticsearch rubbish from the raw data so users
                do not need to see irrelevant stuff
  Returntype  : listref of cleaned hits

=cut

sub clean_results {
  my ($self,$hits) = @_;

  # delete $response_item->{status}{tracks}; # [ENSCORESW-2551]

  # strip away the metadata/configuration field from each search result
  # this will save bandwidth
  # when a trackdb is chosen the client will request all the details by id
  return {hits => { total => 0, hits => []},} if ($hits->{hits}{total} == 0);
  for (my $i = 0; $i < scalar @{ $hits->{hits}{hits} }; $i++ ) {
    for my $good_key (qw/version status hub species type assembly/) {
      # Move expected result keys out of _source document and into the item block, to match existing interface
      $hits->{hits}{hits}->[$i]->{$good_key} = $hits->{hits}{hits}->[$i]->{_source}{$good_key};
    }
    # Older Elasticsearch versions did not have underscores. Change to match output from older implmentation
    for my $corrected_key (qw/id score/) {
      $hits->{hits}{hits}->[$i]{$corrected_key} = $hits->{hits}{hits}->[$i]{'_'.$corrected_key};
    }
    # Clean up any remaining artifacts of the search result
    for my $bad_key (qw/_type _source _index _version created data configuration/) {
      delete $hits->{hits}{hits}->[$i]{$bad_key};
    }
  }

  return $hits;
}


=head2 pager
  Arg[1]      : Hashref - containing query elements appropriate to Search::Elasticsearch
                body => { query => $query }, index => $index_name, type => $type
  Arg[2]      : Callback - code to post-process each of the documents in the result
  Examples    : my $result_list = $model->pager({query => { match => { ... } }, });
  Description : Fetches all the results for the query and buffers any paging that is required
                i.e. to extract more than 10000 records from Elasticsearch in a single request.
  Returntype  : ListRef - A list of all the results for a large query

=cut

sub pager {
  my ($self, $query, $callback) = @_;

  my @result_buffer = ();
  $query->{query} ||= { match_all => {} };
  $query->{size} ||= 10000; # Get the biggest chunks possible (restricted server-side)
  $query->{sort} = '_doc'; # optimisation for ES

  my %prepped_query = $self->_decorate_query(%$query);

  my $iterator = $self->scroll_helper(
    %prepped_query
  );

  while (my $hit = $iterator->next) {
    if ($callback) {
      $hit = $callback->($hit);
    }
    push @result_buffer,$hit;
  }

  return \@result_buffer;
}

=head2 _decorate_query
  
  Arg[1]      : hash - key value pairs of query constraints
  Description : Takes a simple query form adds the index name and type,
                as well as formatting aggregations and such correctly
                for more stringent later versions of Elasticsearch
  Returntype  : hash - the augmented query ready to send to the backend

=cut

sub _decorate_query {
  my ($self, %args) = @_;

  my $config = $self->schema->{trackhub};
  $args{index} = $config->{index_name};
  $args{type}  = $config->{type};

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

=head2 paginate

  Arg[1]      : $result_set, a reference to an Elasticsearch query response
  Arg[2]      : Page number, the page of data requested
  Arg[3]      : Entries per page, the number of records expected per page
  Arg[4]      : Offset, or the 'from' field in Elasticsearch queries.

  Description : Converts result sets into pagination data that the render template can use.
                Elasticsearch only recognises 'from' (offset) and 'size' (limit) and does 
                not paginate on its own

  Return type : hash = (
                  to
                  from
                  total
                  page_size
                  page_count
                  first_page
                  last_page
                  next_page
                  prev_page
                )

=cut

sub paginate {
  my ($self, $result_set, $page, $entries_per_page, $from) = @_;

  return () if $result_set->{hits}{total} == 0;
  my %pagination = (
    from  => $from + 1, # Users are not 0-based
    page  => $page,
    total => $result_set->{hits}{total},
    page_size => $entries_per_page,
    prev_page => undef,
    next_page => undef,
    first_page => undef,
    last_page => undef
  );

  my $page_count = ceil( $result_set->{hits}{total} / $entries_per_page );
  $pagination{page_count} = $page_count;

  # Turn on first/last/next/prev page numbers
  # If left as undef, they should not appear in the pagination view
  if ( $page == 1 ) {
    $pagination{next_page} = $page + 1 if $page_count > 1;
    $pagination{last_page} = $page_count if $page_count > 1;
  } elsif ( $page == $page_count ) {
    # a.k.a. last page
    $pagination{prev_page} = $page_count -1 if $page != 1;
    $pagination{first_page} = 1;
  } else {
    $pagination{prev_page} = $page - 1;
    $pagination{next_page} = $page + 1;
    $pagination{last_page} = $page_count;
    $pagination{first_page} = 1;
  }

  $pagination{to} = $from + @{ $result_set->{hits}{hits} };

  return %pagination;
}

__PACKAGE__->meta->make_immutable;
1;
