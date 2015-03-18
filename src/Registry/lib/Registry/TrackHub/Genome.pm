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
