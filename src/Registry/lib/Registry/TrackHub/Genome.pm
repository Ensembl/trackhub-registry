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

#
# A class to represent genome data which corresponds
# to a stanza in the UCSC genomes file
#
package Registry::TrackHub::Genome;

use strict;
use warnings;

use Registry::Utils::URL qw(read_file);

use vars qw($AUTOLOAD);

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;

  return $self->{$attr};
}

sub new {
  my ($class, %args) = @_;
  
  my $self = \%args;
  bless $self, $class;

  return $self;
}

sub get_trackdb_content {
  my $self = shift;
  defined $self->trackDb or
    die "Cannot get content: undefined trackDb file(s)";

  my $content;
  foreach my $file (@{$self->trackDb}) {
    my $response = read_file($file, { nice => 1 });
    die join("\n", @{$response->{error}})
      if $response->{error};
    
    push @{$content}, $response->{content} =~ s/\r//gr;
  }

  return $content;
}

1;
