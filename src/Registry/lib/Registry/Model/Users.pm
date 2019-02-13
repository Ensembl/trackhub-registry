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

Registry::Model::Users - Functionality for authentication, retrieving user
                         information and trackhub lists

=head1 DESCRIPTION

Inheriting functionality from Catalyst::Model::DBIC::Schema allows this module
to perform authentication. A few utility functions provide syntactic sugar for
user admin/info pages.

Catalyst::Model::DBIC::Schema provides the DBIC schema interface

=cut

package Registry::Model::Users;

use Moose;
use namespace::autoclean;
use Digest;

extends 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    schema_class => 'Registry::User::Schema',
);

=head1 METHODS

=head2 get_user

Retrieve a user Result by their username

=cut

sub get_user {
  my ($self,$username) = @_;
  
  my $user = $self->schema->resultset('User')->find(
    { username => $username }
  );
  return $user;
}

=head2 get_user_by_id

Get a user name from its ID. Returns a string, not a result object

=cut

sub get_user_by_id {
  my ($self,$id) = @_;
  my $user = $self->schema->resultset('User')->find(
    { user_id => $id }
  );
  if ($user) {
    return $user->username;
  }
  return;
}

=head2 get_all_users

Fetch a list of User Result instances from the DB

=cut

sub get_all_users {
  my ($self) = @_;

  my @user_list = $self->schema->resultset('User')->search()->all;
  
  return \@user_list;
}

=head2 delete_user

Given a user object previously returned from this model, tell it to delete itself

=cut

sub delete_user {
  my ($self,$user) = @_;
  $user->delete();
  return;
}

=head2 encode_password

SHA256 plus salting used to obscure password in the database
It modifies the user object in place, so no return value

=cut

sub encode_password {
  my ($self, $user) = @_;

  my $salt = $self->config->{salt};
  
  my $digest = Digest->new('SHA-256');
  $digest->add($salt);
  $digest->add($user->password);
  $user->password($digest->b64digest);
  return;
}

__PACKAGE__->meta->make_immutable;

1;