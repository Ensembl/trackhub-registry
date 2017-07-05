=head1 LICENSE

Copyright [2015-2017] EMBL-European Bioinformatics Institute

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

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

package Registry::Model::Stats;

use Moose;
use namespace::autoclean;
use Catalyst::Exception qw(throw);

use JSON;
use Registry;
use Registry::Utils::File qw(slurp_file);

extends 'Catalyst::Model';

has summary_json => (
	     isa => 'ArrayRef',
	     # isa => 'HashRef',	     
	     is => 'rw',
	     lazy => 1,
	     builder  => '_build_summary_json',
	     # default => sub { {} }
	    );

=head1 METHODS

=head2 fetch_summary

Method to return the summary file used to provide data to the front-end summary stats widget.

=cut

sub fetch_summary {
  my $self = shift;

  return $self->summary_json;
}

=head2 _build_summary_json 

=cut

sub _build_summary_json {
  my $self = shift;
  my $source_file = Registry->config()->{'Model::Stats'}{summary};
  return from_json(slurp_file($source_file));
}


# sub BUILD {
#   my $self = shift;

#   my $source_file = Registry->config()->{'Model::Stats'}{file};
#   $self->json(from_json(slurp_file($source_file)));
# }

__PACKAGE__->meta->make_immutable;

1;
