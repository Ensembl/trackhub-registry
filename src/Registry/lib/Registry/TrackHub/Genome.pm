#
# A class to represent genome data which corresponds
# to a stanza in the UCSC genomes file
#
package Registry::TrackHub::Genome;

use strict;
use warnings;

use Catalyst::Exception;

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


1;
