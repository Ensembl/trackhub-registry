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

use Data::SearchEngine::ElasticSearch::Query;
use Data::SearchEngine::ElasticSearch;

use Registry::Utils::URL qw(file_exists);
use Registry::TrackHub::TrackDB;
use Registry::TrackHub::Translator;

BEGIN { extends 'Catalyst::Controller'; }


=head1 METHODS

=head2 index

Action for the /search URL which takes a query as specified in the home page or the
header, queries the Elasticsearch back-end and presents (faceted) results back to 
the user using pagination.

=cut


sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  my $params = $c->req->params;

  # Basic query check: if empty query params, matches all document
  my ($query_type, $query_body) = ('match_all', {});
  if ($params->{q}) {
    # $query_type = 'match';
    # $query_body = { _all => $params->{q} };
    $query_type = 'query_string';
    $query_body = { query => $params->{q} }; # default field is _all
  } 
  my $facets = 
    {
     species  => { terms => { field => 'species.scientific_name', size => 20 } },
     assembly => { terms => { field => 'assembly.name', size => 20 } },
     hub      => { terms => { field => 'hub.name', size => 20 } },
     type     => { terms => { field => 'type', size => 20 } },
    };

  my $page = $params->{page} || 1;
  $page = 1 if $page !~ /^\d+$/;
  my $entries_per_page = $params->{entries_per_page} || 5;

  my $config = Registry->config()->{'Model::Search'};
  my ($index, $type) = ($config->{trackhub}{index}, $config->{trackhub}{type});

  my $query_args = 
    {
     index     => $index,
     data_type => $type,
     page      => $page,
     count     => $entries_per_page, 
     type      => $query_type,
     query     => $query_body,
     facets    => $facets
    };

  # pass extra (i.e. besides query) parameters as ANDed filters
  my $filters = { public => 1 }; # present only 'public' trackDbs
  
  foreach my $param (keys %{$params}) {
    next if $param eq 'q' or $param eq 'page' or $param eq 'entries_per_page';
    # my $filter = ($param =~ /species/)?'species.tax_id':'assembly.name';
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
    $filters->{$filter} = $params->{$param};
  }
  $query_args->{filters} = $filters if $filters;

  # # now query for the same thing by hub to build the track by hubs view
  # # build aggregation based on hub name taking into account filters
  # my $hub_aggregations; 

  # if (exists $filters->{'species.scientific_name'} and 
  #     defined $filters->{'species.scientific_name'} and not 
  #     exists $filters->{'assembly.name'}) {
  #   $hub_aggregations = 
  #     {
  #      hub_species => { filter => { term => { 'species.scientific_name' => $filters->{'species.scientific_name'} } } }
  #     };
  #   if (exists $filters->{'hub.name'} and defined $filters->{'hub.name'}) {
  #     $hub_aggregations->{hub_species}{aggs} =
  # 	{
  # 	 hub_species_hub => 
  # 	 {
  # 	  filter => { term => { 'hub.name' => $filters->{'hub.name'} } },
  # 	  aggs => { hub => { terms => { field => 'hub.name', size => 1000 } } } 
  # 	 }
  # 	};
  #   } else {
  #     $hub_aggregations->{hub_species}{aggs} = { hub => { terms => { field => 'hub.name', size => 1000 } } };
  #   }
  # } elsif (exists $filters->{'assembly.name'} and 
  # 	   defined $filters->{'assembly.name'} and not 
  # 	   exists $filters->{'species.scientific_name'}) {
  #   $hub_aggregations = 
  #     { 
  #      hub_assembly => { filter => { term => { 'assembly.name' => $filters->{'assembly.name'} } } }
  #     };
  #   if (exists $filters->{'hub.name'} and defined $filters->{'hub.name'}) {
  #     $hub_aggregations->{hub_assembly}{aggs} =
  # 	{
  # 	 hub_assembly_hub => 
  # 	 {
  # 	  filter => { term => { 'hub.name' => $filters->{'hub.name'} } },
  # 	  aggs => { hub => { terms => { field => 'hub.name', size => 1000 } } } 
  # 	 }
  # 	};
  #   } else {
  #     $hub_aggregations->{hub_assembly}{aggs} = { hub => { terms => { field => 'hub.name', size => 1000 } } };
  #   }    
  # } elsif (exists $filters->{'species.scientific_name'} and 
  # 	   defined $filters->{'species.scientific_name'} and
  # 	   exists $filters->{'assembly.name'} and 
  # 	   defined $filters->{'assembly.name'}) {
  #   $hub_aggregations = 
  #     {
  #      hub_species => 
  #      {
  # 	filter => { term => { 'species.scientific_name' => $filters->{'species.scientific_name'} } },
  # 	aggs => 
  # 	{
  # 	 hub_species_assembly =>
  # 	 {
  # 	  filter => { term => { 'assembly.name' => $filters->{'assembly.name'} } }
  # 	 }
  # 	}
  #      }
  #     };
    
  #   if (exists $filters->{'hub.name'} and defined $filters->{'hub.name'}) {
  #     $hub_aggregations->{hub_species}{aggs}{hub_species_assembly}{aggs} =
  # 	{
  # 	 hub_species_assembly_hub =>
  # 	 {
  # 	  filter => { term => { 'hub.name' => $filters->{'hub.name'} } },
  # 	  aggs => { hub => { terms => { field => 'hub.name', size => 1000 } } } 	  
  # 	 }
  # 	};
  #   } else {
  #     $hub_aggregations->{hub_species}{aggs}{hub_species_assembly}{aggs} =
  # 	{ hub => { terms => { field => 'hub.name', size => 1000 } } };
  #   }
  # } else {
  #   if (exists $filters->{'hub.name'} and defined $filters->{'hub.name'}) {
  #     $hub_aggregations = 
  # 	{
  # 	 hub_hub =>
  # 	 {
  # 	  filter => { term => { 'hub.name' => $filters->{'hub.name'} } },
  # 	  aggs => { hub => { terms => { field => 'hub.name', size => 1000 } } }
  # 	 }
  # 	};
  #   } else {
  #     $hub_aggregations = { hub => { terms => { field => 'hub.name', size => 1000 } } };
  #   }
  # }

  # $query_args->{aggregations} = $hub_aggregations if $hub_aggregations;

  my $query = 
    Data::SearchEngine::ElasticSearch::Query->new($query_args);
  my $se = Data::SearchEngine::ElasticSearch->new(nodes => $config->{nodes});
  my ($results, $results_by_hub);

  # do the search
  try {
    $results = $se->search($query);
  } catch {
    if($_->{'msg'} =~ /SearchPhaseExecutionException/gi){
      $c->stash(error_msg => "An unexpected error happened, query parsing failed. Please check your query and try again", template => 'search/results.tt');
    }else{
      Catalyst::Exception->throw( qq/$_/ );
    }

  };
  
  # check hub is available for each search result
  #
  # NOTE:
  # this is introducing a delay in the showing of the search
  # results. Moreover, need to pass the ok status to the view_trackhub
  # action otherwise it will rely on the actual content of the document
  # to show the trackDB status
  #
  # foreach my $item (@{$results->items}) {
  #   my $hub = $item->get_value('hub');

  #   $hub->{ok} = 1;
  #   my $response = file_exists($hub->{url}, { nice => 1 });
  #   $hub->{ok} = 0 if $response->{error};
    
  #   $item->set_value('hub', $hub);
  # }

  if($results){
    $c->stash(query_string    => $params->{q},
              filters         => $params,
              items           => $results->items,
              facets          => $results->facets,
              # aggregations    => $results->{aggregations},
              pager           => $results->pager,
              template        => 'search/results.tt');
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

=head2 advanced_search

Action for /search/advanced_search URL which presents a form where the user can
refine the search by specifying the value of particular fields, i.e. species,
assembly and hub name.

NOTE: this is not active at the moment as it can be equivalently performed by
the user with the faceting system.

=cut

sub advanced_search :Path('advanced') Args(0) {
  my ($self, $c) = @_;

  # get the list of unique species/assemblies/hubs
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{trackhub}{index},
                                            type  => $config->{trackhub}{type},
                                            body => 
                                            {
                                             aggs => {
                                                species   => { terms => { field => 'species.scientific_name', size  => 0 } },
                                                assembly  => { terms => { field => 'assembly.name', size  => 0 } },
                                                hub       => { terms => { field => 'hub.name', size  => 0 } }
                                               }
                                            });
  my $values;
  foreach my $agg (keys %{$results->{aggregations}}) {
    map { push @{$values->{$agg}}, $_->{key} } @{$results->{aggregations}{$agg}{buckets}}
  }
  
  $c->stash(values => $values, template => "search/advanced.tt");
}


=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

__PACKAGE__->meta->make_immutable;

1;
