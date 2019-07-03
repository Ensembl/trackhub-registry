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

=cut

package Registry::User::Schema::Result::User;
use strict;
use warnings;
use parent qw/DBIx::Class::Core/;

__PACKAGE__->table('users');

__PACKAGE__->add_columns(
  user_id => {
    data_type => 'int',
    is_nullable => 0,
    is_auto_increment => 1
  },
  username => {
    data_type => 'varchar',
    is_nullable => 0
  },
  first_name => {
    data_type => 'varchar',
    is_nullable => 1
  },
  last_name => {
    data_type => 'varchar',
    is_nullable => 1
  },
  email => {
    data_type => 'varchar',
    is_nullable => 0
  },
  password => {
    data_type => 'varchar',
    is_nullable => 0
  },
  continuous_alert => {
    data_type => 'int',
    is_nullable => 0
  },
  affiliation => {
    data_type => 'varchar',
    is_nullable => 1
  },
  check_interval => {
    data_type => 'int',
    is_nullable => 1
  },
  auth_key => {
    data_type => 'varchar',
    is_nullable => 1
  }
);

__PACKAGE__->set_primary_key('user_id');
__PACKAGE__->add_unique_constraint(['username']);

__PACKAGE__->has_many(user_role => 'Registry::User::Schema::Result::UserRole', 'user_id');
__PACKAGE__->many_to_many(roles => 'user_role', 'role');


=head2 sqlt_deploy_hook
  Description: Add relevant indexes to the table
  Returntype : undef
  Exceptions : none
  Caller     : general

=cut

sub sqlt_deploy_hook {
  my ($self, $sqlt_table) = @_;

  # $sqlt_table->add_index(name => 'username_idx', fields => ['username', 'password']);
  $sqlt_table->add_index(name => 'key_idx', fields => ['auth_key','username']);
  $sqlt_table->add_index(name => 'alert_idx', fields => ['continuous_alert', 'username']);

  return;
}

1;
