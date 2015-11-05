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

=head1 NAME

Registry::Controller::Search - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

#
# TODO: 
# - Data::SearchEngine::ElasticSearch instance must be initialised
#   with location of nodes from config file
#
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
  my $filters;
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
      Catalyst::Exception::throw("Unrecognised parameter");
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
    Catalyst::Exception->throw( qq/$_/ );
  };
  
  # build and attach hub URL to each search result for browser integration
  foreach my $item (@{$results->items}) {
    my $hub = $item->get_value('hub');
    my $assembly = $item->get_value('assembly');
    my $is_assembly_hub = $hub->{assembly};

    #
    # build UCSC track hub URL
    # look up assembly synonym in translator table
    #
    my $genome_browser_url;
    if ($is_assembly_hub) { # this is an assembly hub
      # see http://genome.ucsc.edu/goldenPath/help/hubQuickStartAssembly.html#blatGbib
      $genome_browser_url->{ucsc} =
	sprintf "http://genome.ucsc.edu/cgi-bin/hgGateway?hubUrl=%s", $hub->{url};
    } elsif (exists $Registry::TrackHub::Translator::synonym2assembly->{lc $assembly->{synonyms}}) {
      # assembly supported by UCSC
      $genome_browser_url->{ucsc} = 
	# sprintf "http://genome.ucsc.edu/cgi-bin/hgTracks?db=%s&hubUrl=%s", $assembly->{synonyms}, $hub->{url};
	sprintf "http://genome.ucsc.edu/cgi-bin/hgHubConnect?db=%s&hubUrl=%s&hgHub_do_redirect=on&hgHubConnect.remakeTrackHub=on", $assembly->{synonyms}, $hub->{url};
    }
    
    #
    # TODO
    #
    # build EnsEMBL track hub URL
    #
    # Connect to ensemblgenomes info DB
    #
    # If human, must see whether it's GRCh37 or newer
    # 

    # check hub is accessible
    $hub->{ok} = 1;
    my $response = file_exists($hub->{url}, { nice => 1 });
    $hub->{ok} = 0 if $response->{error};
    
    $item->set_value('hub', $hub);
    $item->set_value('genome_browser_url', $genome_browser_url);
  }

  $c->stash(query_string    => $params->{q},
	    filters         => $params,
	    items           => $results->items,
	    facets          => $results->facets,
	    # aggregations    => $results->{aggregations},
	    pager           => $results->pager,
	    template        => 'search/results.tt');
    
}

sub view_trackhub :Path('view_trackhub') Args(1) {
  my ($self, $c, $id) = @_;
  my $params = $c->req->params;
  my $urls = 
    {
     ucsc => $params->{ucscUrl},
     ensembl => $params->{ensemblUrl}
    };
  my $assembly_hub = $params->{assembly_hub};
  my $hubok = $params->{hubok};

  my $trackdb;
  try {
    $trackdb = Registry::TrackHub::TrackDB->new($id);
  } catch {
    $c->stash(error_msg => $_);
  };

  $c->stash(trackdb => $trackdb, urls => $urls, assembly_hub => $assembly_hub, hubok => $hubok, template  => "search/view.tt");
}

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

=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
