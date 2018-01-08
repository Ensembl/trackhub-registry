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

Registry::Controller::API::Stats - Endpoints for basic stats

=head1 DESCRIPTION

A controller to provide actions implements endpoints for retrieving 
basic statistics about the content of the registry.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

package Registry::Controller::API::Stats;
use Moose;
use namespace::autoclean;

use JSON;
use Try::Tiny;
use HTTP::Tiny;

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
		    'default'   => 'application/json'
		   );

=head1 METHODS

=head2 complete

Action for /api/stats/complete. Returns complete data with which to build
various stats based on species/assembly/file type on a dedicated page

=cut

sub complete :Local Args(0) ActionClass('REST') { }

=head2 complete_GET

GET method for /api/stats/complete endpoint

=cut

sub complete_GET {
  my ($self, $c) = @_;

  # get all trackdbs
  my $trackdbs = $c->model('Search')->get_trackdbs();
  my $stats;

  # collect:
  # - number of hubs per species/assembly/file type
  # - number of tracks of a specific file type per species/assembly
  # - number of species/assembly/hubs per file type
  foreach my $trackdb (@{$trackdbs}) {
    my $hub = $trackdb->{hub}{name}; # ?!
    $stats->{species}{$trackdb->{species}{scientific_name}}{hubs}{$hub}++;
    $stats->{assemblies}{$trackdb->{assembly}{name}}{hubs}{$hub}++;
    foreach my $type (keys %{$trackdb->{file_type}}) {
      $stats->{species}{$trackdb->{species}{scientific_name}}{file_types}{$type}++;
      $stats->{assemblies}{$trackdb->{assembly}{name}}{file_types}{$type}++;

      $stats->{file_types}{$type}{species}{$trackdb->{species}{scientific_name}}++;
      $stats->{file_types}{$type}{assemblies}{$trackdb->{assembly}{name}}++;
      $stats->{file_types}{$type}{hubs}{$hub}++;
    }
  }

  # adjust the hub based stats, need just the total which is the number
  # of keys in the previously computed stats
  my ($hubs_per_species, $hubs_per_assembly, $hubs_per_file_type);
  map { $hubs_per_species->{$_} = scalar keys %{$stats->{species}{$_}{hubs}} } keys %{$stats->{species}};
  map { $stats->{species}{$_}{hubs} = $hubs_per_species->{$_} } keys %{$stats->{species}};

  map { $hubs_per_assembly->{$_} = scalar keys %{$stats->{assemblies}{$_}{hubs}} } keys %{$stats->{assemblies}};
  map { $stats->{assemblies}{$_}{hubs} = $hubs_per_assembly->{$_} } keys %{$stats->{assemblies}};

  map { $hubs_per_file_type->{$_} = scalar keys %{$stats->{file_types}{$_}{hubs}} } keys %{$stats->{file_types}};
  map { $stats->{file_types}{$_}{hubs} = $hubs_per_file_type->{$_} } keys %{$stats->{file_types}};

  # conclude with something similar for the file_type based counts of species/assemblies
  my ($species_per_file_type, $assemblies_per_file_type);
  map { $species_per_file_type->{$_} = scalar keys %{$stats->{file_types}{$_}{species}} } keys %{$stats->{file_types}};
  map { $stats->{file_types}{$_}{species} = $species_per_file_type->{$_} } keys %{$stats->{file_types}};

  map { $assemblies_per_file_type->{$_} = scalar keys %{$stats->{file_types}{$_}{assemblies}} } keys %{$stats->{file_types}};
  map { $stats->{file_types}{$_}{assemblies} = $assemblies_per_file_type->{$_} } keys %{$stats->{file_types}};

  $self->status_ok($c, entity => $stats);
}

=head2 summary

Action for /api/stats/summary. Returns data suitable to be displayed
in the main page as a brief summary of the content of the data.

=cut

sub summary :Local Args(0) ActionClass('REST') { }

=head2 summary_GET

GET method for /api/stats/summary endpoint.

=cut

sub summary_GET {
  my ($self, $c) = @_;

  my $summary = $c->model('Stats')->fetch_summary();
  $self->status_ok($c, entity => $summary );
}
