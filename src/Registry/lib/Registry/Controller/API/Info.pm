package Registry::Controller::API::Info;
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

=head1 NAME

Registry::Controller::Info - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

# TODO
# could use chained methods, where the start of the chain retrieve all species/assembly/hub aggregations

=head2 species

/api/info/species - returns the list of species

=cut 

sub species : Path('/api/info/species') :Args(0) ActionClass('REST') {}

sub species_GET {
  my ($self, $c) = @_;

  # get the list of unique species, use aggregations
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{index},
					    type  => $config->{type}{trackhub},
					    body => 
					    {
					     aggs => {
						      species   => { terms => { field => 'species.scientific_name', size  => 0 } },
						     }
					    });

  my @species;
  map { push @species, $_->{key} } @{$results->{aggregations}{species}{buckets}};

  $self->status_ok($c, entity => \@species);
}


=head2 assemblies

/api/info/assemblies - returns the list of assemblies organised by species

=cut

sub assemblies :Path('/api/info/assemblies') :Args(0) ActionClass('REST') { }

sub assemblies_GET {
  my ($self, $c) = @_;

  # get the list of unique assemblies, grouped by species
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{index},
					    type  => $config->{type}{trackhub},
					    body => 
					    {
					     aggs => {
						      species => { 
								  terms => { field => 'species.scientific_name', size  => 0 },
								  aggs  => { assembly => { terms => { field => 'assembly.accession', size => 0 } } }
								 },
						     }
					    });

  my $assemblies;
  foreach my $agg (@{$results->{aggregations}{species}{buckets}}) {
    my $species = $agg->{key};
    map { push @{$assemblies->{$species}}, $_->{key} } @{$agg->{assembly}{buckets}};
  }

  $self->status_ok($c, entity => $assemblies);
}

=head2 trackhubs

Return the list of available track data hubs.
Each trackhub is listed with key/value parameters together with
a list of URIs of the resources which corresponds to the trackDbs
beloning to the track hub

=cut

sub trackhubs :Path('/api/info/trackhub') Args(0) ActionClass('REST') { }

sub trackhubs_GET {
  my ($self, $c) = @_;

  # get all trackdbs
  my $trackdbs = $c->model('Search')->get_trackdbs();

  my $trackhubs;
  foreach my $trackdb (@{$trackdbs}) {
    my $hub = $trackdb->{hub}{name};
    $trackhubs->{$hub} = $trackdb->{hub} unless exists $trackhubs->{$hub};

    push @{$trackhubs->{$hub}{trackdbs}},
      {
       species  => $trackdb->{species}{tax_id},
       assembly => $trackdb->{assembly}{accession},
       uri      => $c->uri_for('/api/trackdb/' . $trackdb->{_id})->as_string
      };
  }
  
  my @trackhubs = values %{$trackhubs};
  $self->status_ok($c, entity => \@trackhubs);
}

