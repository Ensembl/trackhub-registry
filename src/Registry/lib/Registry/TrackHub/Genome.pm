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

Registry::TrackHub::Genome - A class representing genome info in a track hub

=head1 DESCRIPTION

A class to represent genome data which corresponds to a stanza in the UCSC genomes file.
This is used by Registry::TrackHub internally when parsing various hub files.
Most of the methods are automatically synthetised and allow to retrieve the attributes
of a genome as specified in the hub genomesFile, e.g. trackDb.

=cut

package Registry::TrackHub::Genome;

use strict;
use warnings;

use Registry::Utils::URL qw(read_file);
use Registry::Utils::Exception;

use vars qw($AUTOLOAD);

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;

  return $self->{$attr};
}

=head1 METHODS

=head2 new

  Arg[1]:     : Hash - constructor parameters
                       assembly - String the assembly name
  Example     : Registry::TrackHub::Genome->new(assembly => 'hg38')
  Description : Build a Registry::TrackHub::Genome object
  Returntype  : Registry::TrackHub::Genome
  Exceptions  : None
  Caller      : Registry::TrackHub
  Status      : Stable

=cut

sub new {
  my ($class, %args) = @_;
  
  my $self = \%args;
  bless $self, $class;

  return $self;
}

=head2 get_trackdb_content

  Arg[1]:     : None
  Example     : $genome->get_trackdb_content()
  Description : Build a Registry::TrackHub::Genome object
  Returntype  : ArrayRef - a list of strings, each one representing
                the content of a trackDb file associated with the 
                genome/assembly
  Exceptions  : Thrown if the genome object does not have trackDb
                files associated
  Caller      : None
  Status      : Stable

=cut

sub get_trackdb_content {
  my $self = shift;
  defined $self->trackDb or
    Registry::Utils::Exception->throw("Cannot get content: undefined trackDb file(s)");

  my $content;
  foreach my $file (@{$self->trackDb}) {
    my $response = read_file($file, { nice => 1 });
    Registry::Utils::Exception( join("\n", @{$response->{error}}) )
      if $response->{error};
    
    push @{$content}, $response->{content} =~ s/\r//gr;
  }

  return $content;
}

1;
