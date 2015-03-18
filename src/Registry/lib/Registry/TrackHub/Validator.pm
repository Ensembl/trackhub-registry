#
#
package Registry::TrackHub::Validator;

use strict;
use warnings;

use Registry::Utils;

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

  defined $args{schema} or die "Undefined JSON schema";
  -e $args{schema} and -f $args{schema} or
    die "Unable to read schema file: $args{schema}";

  my $self = \%args;
  bless $self, $class;

  return $self;
}

sub validate {
  my ($self, $file) = @_;

  my $cmd = sprintf("validate.py -s %s -f %s", $self->{schema}, $file);
  my ($rc, $output) = Registry::Utils::run_cmd($cmd);
  
  # die sprintf "File %s validation failed (schema: %s):\n%s", $file, $self->{schema}, $output
  #   if $output;

  return $output;
}

1;
