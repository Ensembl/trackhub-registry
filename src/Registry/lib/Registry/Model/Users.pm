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

Registry::Model::Users - Functionality for retrieving user information and trackhub lists

=head1 DESCRIPTION

For fetching user profiles from Elasticsearch

=cut

package Registry::Model::Users;

use Moose;
use namespace::autoclean;
use Catalyst::Exception qw(throw);
use List::Util 'max';
use JSON;
use Registry;

extends 'Catalyst::Model::ElasticSearch';

=head1 METHODS

=head2 get_user

Retrieve a user by their username

=cut

sub get_user {
  my ($self,$username) = @_;
  my %query = ( query => { term => { username => $username} });
  %query = $self->_decorate_query(%query);
  my $response = $self->_es->search(%query);
  my $hit;
  if ($response->{hits}{total} == 0) {
    return;
  } else {
    $hit = $response->{hits}{hits}[0]{_source};
    $hit->{id} = $response->{hits}{hits}[0]{_id};
    return $hit;
  }
}

=head2 get_user_by_id

Get a user name from its ID. Returns a string, not a result object

=cut

sub get_user_by_id {
  my ($self,$id) = @_;
  my %query = ( query => { term => {_id => $id}});
  %query = $self->_decorate_query(%query);
  my $response = $self->_es->search(%query);
  if ($response->{hits}{total} == 1) {
    return $response->{hits}{hits}[0]{_source}{username};  
  }
  return;
}

sub get_all_users {
  my ($self) = @_;
  # Don't need to worry about size for a few hundred users, but let's be generous
  my %query = ( query => { match_all => {}}, size => 10000); 
  %query  = $self->_decorate_query(%query);
  my $response = $self->_es->search(%query);
  my @users = map { $_->{_source} } @{$response->{hits}{hits}};
  return \@users;
}

sub delete_user {
  my ($self,$id) = @_;
  my $config = Registry->config()->{'Model::Search'}; # Configs are all bundled together
  my %query = (id => $id, index => $config->{user}{index}, type => $config->{user}{type});
  $self->_es->delete(%query);
  $self->_refresh_index;
}

sub update_profile {
  my ($self,$id,$profile) = @_;
  my %request = $self->_decorate_query(id => $id, body => $profile);
  $self->_es->index(%request);
  $self->_refresh_index;
}

=head2 generate_new_user_id

Create an ID outside the pre-existing ID range to assign to a new user profile

=cut

sub generate_new_user_id {
  my ($self) = @_;
  #my $config = Registry->config()->{'Model::Search'};
  #my %query = (
  #  body => {
  #    query => { 
  #      match_all => {}
  #    },
  #    size => 1,
  #    
  #  },
  #  sort => [ { "username" => "desc"} ],
  #  index => $config->{user}{index},
  #  type => $config->{user}{type}
  #);

  # Ok, let's do this the stupid way since the client library does not seem to 
  # properly support descending sorts. Select all users and find the highest one
  # We're totally fine until we're popular. It's how the previous iteration worked too
  my %query = (
    query => {
      match_all => {}
    },
    size => 10000,
  );
  %query = $self->_decorate_query(%query);
  my $response = $self->search(%query);
  if ($response->{hits}{total} == 0) {
    return 1;
  }
  my $current_max_id = max( map { $_->{_id} } @{$response->{hits}{hits}} );

  return $current_max_id + 1;
}

=head2 _decorate_query

Modifies a bare-bones Elasticsearch query document to include the correct
Index alias and type. 

=cut

sub _refresh_index {
  my ($self) = shift;
  my $config = Registry->config()->{'Model::Search'};
  $self->indices->refresh(index => $config->{user}{index});
}

sub _decorate_query {
  my ($self, %args) = @_;

  my $config = Registry->config()->{'Model::Search'}; # Configs are all bundled together
  $args{index} = $config->{user}{index};
  $args{type}  = $config->{user}{type};
  #$args{body}{sort} = $args{sort};
  $args{body}{query} = $args{query};
  delete $args{query};
  #delete $args{sort};

  # Perform any necessary query cleanup here:
  
  return %args;
}


__PACKAGE__->meta->make_immutable;

1;