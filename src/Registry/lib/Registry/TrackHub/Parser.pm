#
# A parser of trackDB configuration files
#
package Registry::TrackHub::Parser;

use strict;
use warnings;

use Registry::Utils::URL qw(read_file);
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

  defined $args{files} || die "Undefined files parameter";
  my $self = \%args || {};
  
  bless $self, $class;
  return $self;
}

sub parse {
  my $self = shift;

  foreach (@{$self->files}) {
    my $response = read_file($_, { 'nice' => 1 });
    Catalyst::Exception->throw(join("\n", @{$response->{error}})) 
	if $response->{error};
    
  }
}

1;
