=head1 LICENSE

Copyright [2015-2019] EMBL-European Bioinformatics Institute

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

Registry::TrackHub::Tree - Class for the trackDB hierarchy

=head1 SYNOPSIS

my $ctree = Registry::TrackHub::Tree->new({ id => 'root' });
  $self->_make_configuration_tree($ctree, $tracks);

=head1 DESCRIPTION

A tree class for representing the hierarchy of tracks in a track db file, i.e. a forest in the most generic case

=cut

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

=head2 new

  Arg[1]:     : HashRef - node parameters
  Example     : my $ctree = Registry::TrackHub::Tree->new({ id => 'root' });
  Description : Constructor, make a node of the tree
  Returntype  : Registry::TrackHub::Tree
  Exceptions  : None
  Caller      : Registry::TrackHub::Translator
  Status      : Stable

=cut

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

=head2 create_node

  Arg [1]     : String - the id of the node (required)
  Arg [2]     : HashRef - node data (optional)
  Example:    : $tree->create_node('nodeid', { 'key' => 'value'} );
  Description : Create a node of the hierarchy
  Returntype  : Registry::TrackHub::Tree
  Exceptions  : None
  Caller      : Registry::TrackHub::Translator::_make_configuration_tree
  Status      : Stable

=cut

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

=head2 get_node

  Arg [1]     : String - the id of the node (required)
  Example:    : my $parent = $tree->get_node($node->{'parent'});
  Description : Create a node in the hierarchy by id
  Returntype  : Registry::TrackHub::Tree
  Exceptions  : None
  Caller      : Registry::TrackHub::Translator::_make_configuration_tree
  Status      : Stable

=cut

sub get_node {
  my ($self, $id) = @_;
  return $self->{tree_ids}{$id};
}

=head2 get_all_nodes

Not implemented

=cut

sub get_all_nodes {
}

=head2 is_leaf

Not used. Returns whether or not the node is a leaf of the tree

=cut

sub is_leaf { return !$_[0]->has_child_nodes; }

=head2 has_child_nodes

Not used. Returns whether the node is a parent of some other nodes

=cut

sub has_child_nodes {
  return scalar @{shift->child_nodes}?1:0;
}

=head2 first_child

Not used. Returns the first child of the node

=cut

sub first_child {
  return shift->child_nodes->[0] || undef;
}

=head2 last_child

Not used. Returns whether the last child of the node

=cut

sub last_child {
  return shift->child_nodes->[-1] || undef;
}


=head2 previous

Not used. Returns previous sibling of a child node

=cut

# previous|next_sibling attributes are set when
# child is appended
sub previous { return $_[0]->previous_sibling; }

=head2 next

Not used. Returns next sibling of a child node

=cut

sub next { return $_[0]->next_sibling; }

=head2 append

Add a child to the node

=cut

sub append { return $_[0]->append_child($_[1]); }

=head2 append_child

Appends a child node (or creates a new child node before appending).
@param New node 
@return New node if success, undef otherwise

=cut

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
