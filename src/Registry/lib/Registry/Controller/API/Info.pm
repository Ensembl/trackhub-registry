=head1 LICENSE

Copyright [2015-2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Registry::Controller::API::Info;
use Moose;
use namespace::autoclean;

use JSON;
use Try::Tiny;
use HTTP::Tiny;

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

=head2 version

Action for /api/info/version, returns the version of the API

=cut 

sub version :Local :Args(0) :ActionClass('REST') { }

sub version_GET {
  my ($self, $c) = @_;

  $self->status_ok($c, entity => { release => $Registry::VERSION });
}

=head2 ping

Action for /api/info/ping

=cut

sub ping :Local Args(0) ActionClass('REST') { }

sub ping_GET {
  my ($self, $c) = @_;

  my $nodes = Registry->config()->{'Model::Search'}{nodes};
  my $es_url;
  # can have multiple nodes specified in the configuration
  if (ref $nodes eq 'ARRAY') {
    $es_url = sprintf "http://%s", $nodes->[0]; # take the first node as URL to ping
  } else {
    $es_url = sprintf "http://%s", $nodes;
  }
  my $ping = (HTTP::Tiny->new()->request('GET', $es_url)->{status} eq '200')?1:0;

  $self->status_ok($c, entity => { ping => $ping }) if $ping;
  $self->status_gone($c, message => 'Storage is unavailable') unless $ping;
}


# TODO
# could use chained methods, where the start of the chain retrieve all species/assembly/hub aggregations

=head2 species

/api/info/species - returns the list of species

=cut 

sub species :Local :Args(0) ActionClass('REST') {}

sub species_GET {
  my ($self, $c) = @_;

  # get the list of unique species, use aggregations
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{trackhub}{index},
					    type  => $config->{trackhub}{type},
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

sub assemblies :Local :Args(0) ActionClass('REST') { }

sub assemblies_GET {
  my ($self, $c) = @_;

  # get the list of unique assemblies, grouped by species
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{trackhub}{index},
					    type  => $config->{trackhub}{type},
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

=head2

Return the number of hubs per assembly, specified as name

=cut

sub hubs_per_assembly :Local Args(1) ActionClass('REST') {}

sub hubs_per_assembly_GET {
  my ($self, $c, $assembly_name) = @_;

  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{trackhub}{index},
					    type  => $config->{trackhub}{type},
					    body => 
					    {
					     aggs => {
						      assembly => { terms => { field => 'assembly.name', size  => 0 } },
						     }
					    });

  # facets counts are the number of trackDBs per assembly, which is the same as the same
  # as the number of hubs as each hub as one trackDB per assembly
  my $hubs = 0;
  map { $hubs = $_->{doc_count} if $_->{key} eq $assembly_name } @{$results->{aggregations}{assembly}{buckets}};

  $self->status_ok($c, entity => { tot => $hubs });
}

=head2 trackhubs

Return the list of available track data hubs.
Each trackhub is listed with key/value parameters together with
a list of URIs of the resources which corresponds to the trackDbs
beloning to the track hub

=cut

sub trackhubs :Local Args(0) ActionClass('REST') { }

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
       uri      => $c->uri_for('/api/search/trackdb/' . $trackdb->{_id})->as_string
      };
  }
  
  my @trackhubs = values %{$trackhubs};
  $self->status_ok($c, entity => \@trackhubs);
}
