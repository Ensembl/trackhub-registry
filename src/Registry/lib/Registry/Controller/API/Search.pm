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

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Controller::API::Search - endpoints for programmatic search

=head1 DESCRIPTION

This is a controller providing actions implementing endpoints for doing
programmatic search of track hubs.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

package Registry::Controller::API::Search;
use Moose;
use namespace::autoclean;

use JSON;
use Try::Tiny;

use Data::SearchEngine::ElasticSearch::Query;
use Data::SearchEngine::ElasticSearch;

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
		    'default'   => 'application/json',
		    # map => {
		    # 	    'text/plain' => ['YAML'],
		    # 	   }
		   );

=head1 METHODS

=head2 search

Action for /api/search endpoint

=cut

sub search :Path('/api/search') Args(0) ActionClass('REST') {
  my ( $self, $c ) = @_;

  my $params = $c->req->params;
  my $page = $params->{page} || 1;
  $page = 1 if $page !~ /^\d+$/;
  my $entries_per_page = $params->{entries_per_page} || 5;

  if ($params->{all}) {
    $page = 1;
    $entries_per_page = 10000;
  }
  
  $c->stash( page => $page, entries_per_page => $entries_per_page );
}

=head2 search_POST

POST method implementation for /api/search endpoint

=cut

sub search_POST {
  my ($self, $c) = @_;

  return $self->status_bad_request($c, message => "Missing data")
    unless defined $c->req->data;

  my $params = $c->req->params;
  my $data = $c->req->data;

  my ($query_type, $query_body) = ('match_all', {});
  my $query = $data->{query};
  
  if ($query) {
    # $query_type = 'match';
    # $query_body = { _all => $query };
    $query_type = 'query_string';
    $query_body = { query => $query }; # default field is _all
  }

  my $config = Registry->config()->{'Model::Search'};
  my ($index, $type) = ($config->{trackhub}{index}, $config->{trackhub}{type});

  # process filters, i.e. species, assembly, hub
  my $filter_combine =
    {
     public => 'and' 
    };
  my $filters = { public => 1 }; # present only 'public' hubs
  
  $filters->{'species.scientific_name'} = $data->{species} and $filter_combine->{'species.scientific_name'} = 'and'
    if $data->{species};

  # if assembly is provided extend the search to both the
  # name and synonyms to allow fetching 
  if ($data->{assembly}) {
    # $filters->{'assembly.name'} = $data->{assembly};
    # $filters->{'assembly.synonyms'} = $data->{assembly};

    # # change the logical operator to OR so that search is
    # # capable of fetching results in either cases
    # $filter_combine->{'assembly.name'} = 'or';
    # $filter_combine->{'assembly.synonyms'} = 'or';
    
    # ENSCORESW-2039
    # put assembly parameter as query string, otherwise cannot find some assemblies
    # due to the way assembly.synonyms and assembly.name are (not) indexed in combination
    # with the use of a filter
    if ($query) {
      $query_body->{query} .= sprintf " AND %s", $data->{assembly};
    } else {
      $query_type = 'query_string';
      $query_body = { query => $data->{assembly} };
    }
  }
  $filters->{'assembly.accession'} = $data->{accession} and $filter_combine->{'assembly.accession'} = 'and'
    if $data->{accession};
  $filters->{'hub.name'} = $data->{hub} and $filter_combine->{'hub.name'} = 'and'
    if $data->{hub};
  $filters->{type} = $data->{type} and $filter_combine->{'type'} = 'and'
    if $data->{type};

  my $query_args = 
    {
     index     => $index,
     data_type => $type,
     page      => $c->stash->{page},
     count     => $c->stash->{entries_per_page}, 
     type      => $query_type,
     query     => $query_body,
    };  
  $query_args->{filters} = $filters if $filters;

  # do the search
  my $results;
  my $se = Data::SearchEngine::ElasticSearch->new(nodes => $config->{nodes});
  
  try {
    $results = $se->search(Data::SearchEngine::ElasticSearch::Query->new($query_args), $filter_combine);
  } catch {
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };

  # build the JSON response
  my $response = { total_entries => $results->pager->total_entries };

  # On recent installations, we cannot simply assign the response items to the array 
  # of Data::SearchEngine::Item search results.
  # Catalyst::Action::Serialize::JSON complains it cannot deal with blessed references.
  # Build the response items as an array of simple hash references.
  foreach my $item (@{$results->items}) {
    my $response_item = $item->{values};
    $response_item->{id} = $item->{id};
    $response_item->{score} = $item->{score};
    delete $response_item->{status}{tracks};

    # strip away the metadata/configuration field from each search result
    # this will save bandwidth
    # when a trackdb is chosen the client will request all the details by id
    # remove also other fields the user is not interested in
    map { delete $response_item->{$_} } qw ( source _index owner _version created data configuration );

    push @{$response->{items}}, $response_item;
  }
  $response->{items} = [] unless scalar @{$results->items};

  # strip away the metadata/configuration field from each search result
  # this will save bandwidth
  # when a trackdb is chosen the client will request all the details by id
  # map { delete $_->{values}{data}; delete $_->{values}{configuration} } @{$response->{items}};

  $self->status_ok($c, entity => $response);
}

=head2 biosample_search

Support querying by list of BioSample IDs

=cut

sub biosample_search :Path('/api/search/biosample') Args(0) ActionClass('REST') { }

=head2 biosample_search_POST

Implement POST method for /api/search/biosample endpoint

=cut

sub biosample_search_POST {
  my ($self, $c) = @_;

  use Data::Dumper;

  return $self->status_bad_request($c, message => "Missing list of biosample IDs")
    unless defined $c->req->data;
  my $biosample_ids = $c->req->data->{ids};
  return $self->status_bad_request($c, message => "Empty list of biosample IDs")
    unless scalar @{$biosample_ids};
  
  # prepare query
  # it's a simple filtered query with 'terms' filter to find the
  # docs that have any of the listed values
  #
  # WARNING
  # the ids must be lowercased since the biosample id field is analysed
  # i.e. reindexing the data would be more painful
  #
  $_ = lc for @{$biosample_ids};

  my $query = {
	       filtered => {
			    filter => {
				       terms => { 
				       		 biosample_id => $biosample_ids
				       		}
				      }
			   }
	      };
  my $config = Registry->config()->{'Model::Search'};
  my %args =
    (
     index => $config->{trackhub}{index},
     type  => $config->{trackhub}{type},
     body  => { query => $query },
     search_type => 'scan'
    );

  my $results;
  try {
    # do not care about scoring, use scan&scroll for efficient querying
    my $scroll = $c->model('Search')->_es->scroll_helper(%args);
    while (my $result = $scroll->next) {
      # find which IDs this trackdb refers to
      my %match_ids;
      foreach my $track_metadata (@{$result->{_source}{data}}) {
	map { $match_ids{uc $_}++ if exists $track_metadata->{biosample_id} and $track_metadata->{biosample_id} eq uc $_ } 
	  @{$biosample_ids};
      } 
      # strip away various fields from each search result
      # when a trackdb is chosen the client will request all the details by id
      map { delete $result->{_source}{$_} } qw ( owner source version status created file_type public updated data configuration );
      $result->{_source}{id} = $result->{_id};
      
      map { push @{$results->{$_}}, $result->{_source} } keys %match_ids;
    }
  } catch {
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };

  $self->status_ok($c, entity => $results?$results:{});
}

=head2 trackdb

/api/search/trackdb/:id - return a trackDB document by ID.
This is supposed to be called by an agent to retrieve one of the
available results after it has performed a search

=cut 

sub trackdb :Local Args(1) ActionClass('REST') {
  my ($self, $c, $doc_id) = @_;

  # if the doc with that ID doesn't exist, ES throws exception
  # intercept but do nothing, as the GET method will handle
  # the situation in a REST appropriate way.
  eval { $c->stash(trackdb => $c->model('Search')->get_trackhub_by_id($doc_id)); };
}

=head2 trackdb_GET

GET method for /api/search/trackdb/:id endpoint

=cut

sub trackdb_GET {
  my ($self, $c, $doc_id) = @_;

  my $trackdb = $c->stash()->{trackdb};
  if ($trackdb) {
    # strip away the metadata field
    delete $trackdb->{data};

    $self->status_ok($c, entity => $trackdb);
  } else {
    $self->status_not_found($c, message => "Could not find trackdb doc (ID: $doc_id)");    
  }
}

__PACKAGE__->meta->make_immutable;

1;
