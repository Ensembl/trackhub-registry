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

Registry::Controller::Search - 

=head1 DESCRIPTION

=cut

package Registry::Controller::Search;
use Moose;
use namespace::autoclean;

use Try::Tiny;
use Catalyst::Exception;

use Registry::Utils::URL qw(file_exists);
use Registry::TrackHub::TrackDB;
use Registry::TrackHub::Translator;

BEGIN { extends 'Catalyst::Controller'; }


=head1 METHODS

=head2 index

Action for the / page after the query form has been submitted, generating ?q options.
Queries the Elasticsearch back-end and presents (faceted) results back to 
the user using pagination.

=cut


sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  my $params = $c->req->params;

  # Basic query check: if empty query params, matches all document
  # This should all be refactored into a Search model.
  my $first_constraint;
  my ($query_body, $query_field);
  if ($params->{q}) {
    if ($params->{q} !~ /\w/) {
      $c->stash(error_msg => 'Unintelligible query string - your query must contain something resembling words or named fields', template => 'index.tt');
      return;
    } else {
      $first_constraint = { query_string => { query => $params->{q} }};
    }
  } else {
    $c->log->debug('Using the most lame default query');
    $query_body = {};
    $query_field = 'match_all';
    $first_constraint = { $query_field => $query_body };
  }
  
  # Elasticsearch recommend using composite aggregation for getting the full list of facets
  # We could conceivably paginate the facets.
  my $facets = {
    species  => { terms => { field => 'species.scientific_name', size => 100, order => {"_key" => "asc" }} },
    assembly => { terms => { field => 'assembly.name', size => 50 } },
    hub      => { terms => { field => 'hub.name',size => 30 } },
    type     => { terms => { field => 'type'} },
  };

  my $page = $params->{page} // 1;
  $page = 1 if $page !~ /^\d+$/;
  my $entries_per_page = $params->{entries_per_page} // 5;
  my $from = 0; # zero-based. one excludes the first result
  if ($page != 1) {
    $from = $page * $entries_per_page;
  }

  my %query_args = (
    from             => $from,
    size             => $entries_per_page, 
    query            => { bool => { must => [ $first_constraint ]}},
    aggregations     => $facets
  );

  # pass extra (i.e. besides query) parameters as additional constraints to the user query
  my @filters; # present only 'public' trackDbs
  push @filters, { term => { public => 'true' }};
  foreach my $param (keys %{$params}) {
    next if $param eq 'q' or $param eq 'page' or $param eq 'entries_per_page';
    
    my $filter;
    if ($param =~ /species/) {
      $filter = 'species.scientific_name';
    } elsif ($param =~ /assembly/) {
      $filter = 'assembly.name';
    } elsif ($param =~ /hub/) {
      $filter = 'hub.name';
    } elsif ($param =~ /type/) {
      $filter = 'type';
    } else {
      Catalyst::Exception->throw("Unrecognised parameter: $param");
    }
    push @filters, { term => { $filter => $params->{$param} } };
  }
  push @{ $query_args{query}->{bool}->{must}}, @filters;

  my ($results, $results_by_hub);
  # do the search
  try {
    $results = $c->model('Search')->search_trackhubs(%query_args);
  } catch {
    Catalyst::Exception->throw( qq/$_/ );
  };

  # User form doesn't want to handle Elasticsearch annotation in the results
  my @clean_results = map { $_->{_source}{id} = $_->{_id}; $_->{_source} } @{ $results->{hits}{hits}};

  if($results){
    my %pagination = $c->model('Search')->paginate($results, $page, $entries_per_page, $from);
    $c->stash(
      query_string    => $params->{q},
      filters         => $params,
      items           => \@clean_results,
      aggregations    => $results->{aggregations},
      template        => 'search/results.tt',
      %pagination
    );
  }
}

=head2 view_trackhub

Action for /search/view_trackhub/:id triggered by the "View Info" button presented
by each search result. This allow the user to view more detailed information about
the trackdb with the given :id.

=cut

sub view_trackhub :Path('view_trackhub') Args(1) {
  my ($self, $c, $id) = @_;
  my $trackdb;

  try {
    $trackdb = Registry::TrackHub::TrackDB->new($id);
  } catch {
    $c->stash(error_msg => $_);
  };

  $c->stash(trackdb => $trackdb, template  => "search/view.tt");
}


=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

__PACKAGE__->meta->make_immutable;

1;
