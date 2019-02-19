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

Registry::Controller::API::Search - endpoints for programmatic search

=head1 DESCRIPTION

This is a controller providing actions implementing endpoints for doing
programmatic search of track hubs.

=cut

package Registry::Controller::API::Search;
use Moose;
use namespace::autoclean;

use JSON;
use Try::Tiny;

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
  print "Per page value request: $entries_per_page\n";
  if ( $params->{entries_per_page} * $page > 10000 ) {
    $c->status_bad_request($c, message => "Search result too large. Use the ?all parameter to fetch large amounts of data");
  }

  if ($params->{all}) {
    $c->stash->{all} = 1;
  }

  
  $c->stash( page => $page, entries_per_page => $entries_per_page );
}

=head2 search_POST

POST method implementation for /api/search endpoint

=cut

sub search_POST {
  my ($self, $c) = @_;

  if (! defined $c->req->data) {
    return $self->status_bad_request($c, message => "Missing message body in request");
  }
  my $data = $c->req->data;

  my $query_body = {};

  # do the search
  my $results;

  if ($c->stash->{all} == 1) {

    my $result_list = $c->model('Search')->pager(
      undef, 
      sub {
        my $thing = shift;
        for my $corrected_key (qw/id score type/) {
          $thing->{$corrected_key} = $thing->{'_'.$corrected_key};
          delete $thing->{'_'.$corrected_key}
        }
        for my $unpacked_key (qw/hub status species assembly/) {
          $thing->{$unpacked_key} = $thing->{_source}{$unpacked_key};
        }
        for my $discarded_key (qw/_index sort _source/) {
          delete $thing->{$discarded_key};
        }
        return $thing;
      });

    $results = { 
      total_entries => scalar @$result_list,
      items => $result_list
    };
  } else {
    $results = $c->model('Search')->api_search(
      $data->{query},
      $c->stash->{page},
      $c->stash->{entries_per_page},
      $data->{species},
      $data->{assembly},
      $data->{accession},
      $data->{hub},
      $data->{type}
    );
  }

  $self->status_ok($c, entity => $results);
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
    terms => { 
          biosample_id => $biosample_ids
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
    # when it is available via Perl interface for ES 6.x
    my $hits = $c->model('Search')->_se->search(%args);

    while (my $result = shift @$hits) {
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

=head2 trackdb_all 

/api/search/all

Used by trackfind to mine the Trackhub Registry for metadata. Public hubs only
Not publicised for general use as it will place stress on the web server if widely used.
Previous loading on servers has not come close to stressing the host, hence no efforts made
to page the outputs for the consumer.

=cut

sub trackdb_all :Path('/api/search/all') ActionClass('REST') {

}

=head2 trackdb_all_GET

GET handler for /api/search/all
See also Catalyst::Action::REST

=cut

sub trackdb_all_GET {
  my ($self, $c) = @_;

  my $trackdbs = $c->model('Search')->get_trackdbs(
    query => { 
      term => { public => "true"}
    }, 
    sort => ["_doc"]
  );

  # Clean out some keys we don't want/need to leak to users
  for (my $i=0; $i < scalar @$trackdbs; $i++) {
    delete $trackdbs->[$i]->{_source}{owner}; # Anonymise output data.
    delete $trackdbs->[$i]->{_index};
    delete $trackdbs->[$i]->{_type};
    delete $trackdbs->[$i]->{_score};
    delete $trackdbs->[$i]->{sort};
  }
  $self->status_ok($c, entity => $trackdbs);
}

__PACKAGE__->meta->make_immutable;

1;
