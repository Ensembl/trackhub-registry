package Registry::Controller::Info;
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

# sub assemblies :Path('/api/info/assemblies') :Args(0) ActionClass('REST') { }

# sub assemblies_GET {
#   my ($self, $c) = @_;

#   my $params = $c->req->params;
#   my $page = $params->{page} || 1;
#   $page = 1 if $page !~ /^\d+$/;
#   my $entries_per_page = $params->{entries_per_page} || 5;

#   $c->stash( page => $page, entries_per_page => $entries_per_page );
# }
