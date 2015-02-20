#
# A class to represent a translator from UCSC-style trackdb
# documents to the corresponding JSON specification
#
package Registry::TrackHub::Translator;

use strict;
use warnings;

use JSON;
use Catalyst::Exception;

use Registry::TrackHub;

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
  
  $args{version} ||= Registry->config()->{TrackHub}{json}{version};
  defined $args{version} or Catalyst::Exception->throw("Undefined version");

  my $self = \%args;
  bless $self, $class;

  return $self;
}


1;
