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

Registry::Controller::API::Info - Endpoints for retrieving service and track hub information

=head1 DESCRIPTION

A controller to provide actions implements endpoints for retrieving information about
the service and the content of the Registry.

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

=head1 METHODS

=head2 version

Action for /api/info/version, returns the version of the API

=cut 

sub version :Local :Args(0) :ActionClass('REST') { }

=head2 version_GET

GET method for /api/info/version

=cut

sub version_GET {
  my ($self, $c) = @_;

  $self->status_ok($c, entity => { release => $Registry::VERSION });
}

=head2 ping

Action for /api/info/ping, check the service is alive

=cut

sub ping :Local Args(0) ActionClass('REST') { }

=head2 ping_GET

GET method for /api/ping endpoint

=cut

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

=head2 species_GET

GET method for /api/info/species endpoint

=cut

sub species_GET {
  my ($self, $c) = @_;

  # get the list of unique species, use aggregations
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(
              index => $config->{trackhub}{index},
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

=head2 assemblies_GET

GET method for /api/info/assemblies endpoint

=cut

sub assemblies_GET {
  my ($self, $c) = @_;

  # get the list of unique assemblies, with name, synonyms and accession, grouped by species
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(
    index => $config->{trackhub}{index},
    type  => $config->{trackhub}{type},
    body => 
    {
      aggs => {
        public => {
          filter => { term => { public => 1 } },
            aggs => {
              species => {
                terms => { field => 'species.scientific_name', size  => 0 },
                aggs  => {
                  ass_name => {
                    terms => { field => 'assembly.name', size => 0 },
                    aggs => {
                      ass_syn => {
                        terms => { field => 'assembly.synonyms', size => 0 },
                        aggs => {
                          ass_acc => { terms => { field => 'assembly.accession', size => 0 } }
                        }
                      }
                    }
                  }
                }
              },
            }
          }
       }
    });

  my $assemblies;
  foreach my $species_agg (@{$results->{aggregations}{public}{species}{buckets}}) {
    my $species = $species_agg->{key};
    foreach my $ass_name_agg (@{$species_agg->{ass_name}{buckets}}) {
      my $ass_name = $ass_name_agg->{key};
      foreach my $ass_syn_agg (@{$ass_name_agg->{ass_syn}{buckets}}) {
        my $ass_syn = $ass_syn_agg->{key};
        foreach my $ass_acc_agg (@{$ass_syn_agg->{ass_acc}{buckets}}) {
          my $ass_acc = $ass_acc_agg->{key};
          push @{$assemblies->{$species}},
            {
             name => $ass_name,
             synonyms => [ $ass_syn ],
             accession => $ass_acc
            }
        }
      }
    }
  }

  $self->status_ok($c, entity => $assemblies);
}

=head2 hubs_per_assembly

Return the number of hubs per assembly, specified as name

=cut

sub hubs_per_assembly :Local Args(1) ActionClass('REST') {}

=head2 hubs_per_assembly_GET

GET method for /api/info/hubs_per_assembly endpoint

=cut

sub hubs_per_assembly_GET {
  my ($self, $c, $assembly) = @_;

  my $term_field = 'assembly.name';
  $term_field = 'assembly.accession' if $assembly =~ /^GCA/;
  
  my $config = Registry->config()->{'Model::Search'};
  my $results = $c->model('Search')->search(index => $config->{trackhub}{index},
                                            type  => $config->{trackhub}{type},
                                            body => 
                                            {
                                             aggs => {
                                                assembly => { terms => { field => $term_field, size  => 0 } },
                                               }
                                            });

  # facets counts are the number of trackDBs per assembly, which is the same as the same
  # as the number of hubs as each hub as one trackDB per assembly
  my $hubs = 0;
  map { $hubs = $_->{doc_count} if lc $_->{key} eq lc $assembly } @{$results->{aggregations}{assembly}{buckets}};

  $self->status_ok($c, entity => { tot => $hubs });
}

=head2 tracks_per_assembly

Return the number of tracks per assembly, specified as name

=cut

sub tracks_per_assembly :Local Args(1) ActionClass('REST') {}

=head2 tracks_per_assembly_GET

GET method for /api/info/tracks_per_assembly endpoint

=cut

sub tracks_per_assembly_GET {
  my ($self, $c, $assembly_name) = @_;

  my $config = Registry->config()->{'Model::Search'};

  # Can't do with simple term filter or query, as the endpoint 
  # should support case insensitive search, but the assembly.name
  # field is not analysed 
  # my $query = {
  # 	       filtered => {
  # 	       		    filter => {
  # 	       			       term => { 
  # 	       			       		 'assembly.name' => $assembly_name
  # 	       				       }
  # 	       			      }
  # 	       		   }
  # 	      };
  # my %args =
  #   (
  #    index => $config->{trackhub}{index},
  #    type  => $config->{trackhub}{type},
  #    body  => { query => $query },
  #    search_type => 'scan'
  #   );
  
  # my $tracks = 0;
  # try {
  #   my $scroll = $c->model('Search')->_es->scroll_helper(%args);
  #   while (my $result = $scroll->next) {
  #     $tracks += scalar @{$result->{_source}{data}};
  #   }
  # } catch {
  #   $c->go('ReturnError', 'custom', [qq{$_}]);
  # };
  my $trackdbs = $c->model('Search')->get_trackdbs();
  my $tracks = 0;
  map { $tracks += scalar @{$_->{data}} if lc $_->{assembly}{name} eq lc $assembly_name } @{$trackdbs};

  $self->status_ok($c, entity => { tot => $tracks });
}

=head2 trackhubs

Action for /api/info/trackhub.

Return the list of available track data hubs. Each trackhub is listed with key/value parameters together with
a list of URIs of the resources which corresponds to the trackDbs beloning to the track hub

=cut

sub trackhubs :Local Args(0) ActionClass('REST') { }

=head2 trackhubs_GET

GET method for /api/info/trackhubs endpoint

=cut

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
