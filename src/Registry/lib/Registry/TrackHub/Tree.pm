#
# A tree class for representing the hierarchy of tracks 
# in a track db file, i.e. a forest in the most generic case
#
package Registry::TrackHub::Tree;

use strict;
use warnings;

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
  my ($class, $args) = @_;

  my $self;
  $self->{tree_ids} = {}; # a complete list of unique identifiers in the tree, and their nodes
  $self->{$_}       = $args->{$_} for keys %{$args || {}};
  bless $self, $class;

  defined $self->{id} or die "Undefined node id";
  $self->{tree_ids}{$self->{id}} = $self;

  return $self;
}

sub create_node {
}

sub get_node {
}

sub parent_node {
}

sub get_all_nodes {
}

sub has_child_nodes {
}

sub previous_sibling {
}

sub next_sibling {
}

sub append_child {
}

sub prepend_chid {
}

1;
