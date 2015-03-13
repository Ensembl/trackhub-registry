#
# A tree class for representing the hierarchy of tracks 
# in a track db file, i.e. a forest in the most generic case
#
package Registry::TrackHub::Tree;

use strict;
use warnings;

use Registry::TrackHub::Tree;

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

  my $self =
    {
     # id => 'random string??',
     data                 => {},
     child_nodes          => [],
     parent_node          => 0,
     next_sibling         => 0,
     previous_sibling     => 0,
     tree_ids             => {} # a complete list of unique identifiers in the tree, and their nodes
    };
  # overwrites previous args
  $self->{$_} = $args->{$_} for keys %{$args || {}};
  bless $self, $class;

  defined $self->{id} or die "Undefined node id";
  $self->{tree_ids}{$self->{id}} = $self;

  return $self;
}

sub create_node {
  my ($self, $id, $data) = @_;
  defined $id or die "Undefined id";
  defined $data or die "Undefined data";

  if (exists $self->tree_ids->{$id}) {
    my $node = $self->get_node($id);
    $node->data->{$_} = $data->{$_} for keys %$data;
    
    return $node;
  }
  
  return Registry::TrackHub::Tree->new({ id        => $id,
					 data      => $data || {},
					 tree_ids  => $self->tree_ids,
				       });
}

sub get_node {
  my ($self, $id) = @_;
  return $self->{tree_ids}{$id};
}

sub get_all_nodes {
}

sub is_leaf { return !$_[0]->has_child_nodes; }

sub has_child_nodes {
  return scalar @{shift->child_nodes}?1:0;
}

sub first_child {
  return shift->child_nodes->[0] || undef;
}

sub last_child {
  return shift->child_nodes->[-1] || undef;
}

# previous|next_sibling attributes are set when
# child is appended
sub previous { return $_[0]->previous_sibling; }

sub next { return $_[0]->next_sibling; }

sub append { return $_[0]->append_child($_[1]); }

# Appends a child node (or creates a new child node before appending)
# @param New node 
# @return New node if success, undef otherwise
sub append_child {
  my ($self, $child) = @_;

  $child->parent_node($self);
  if ($self->has_child_nodes) {
    $child->previous_sibling($self->last_child);
    $self->last_child->next_sibling($child);
  }
  push @{$self->child_nodes}, $child;
  return $child;
}

# sub prepend { return $_[0]->prepend_child($_[1]); }

# sub prepend_chid {
#   my $self = shift;
# }

1;
