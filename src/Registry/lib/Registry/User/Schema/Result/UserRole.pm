=head1 LICENSE

Copyright [2015-2023] EMBL-European Bioinformatics Institute

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

package Registry::User::Schema::Result::UserRole;
use strict;
use warnings;
use parent qw/DBIx::Class::Core/;

__PACKAGE__->table('user_roles');
__PACKAGE__->add_columns(
  user_id => {
    data_type => 'int',
    nullable => 0,
    is_foreign_key => 1
  },
  role_id => {
    data_type => 'int',
    nullable => 0,
    is_foreign_key => 1
  }
);

__PACKAGE__->set_primary_key('user_id','role_id');

__PACKAGE__->belongs_to(role => 'Registry::User::Schema::Result::Role', 'role_id');
__PACKAGE__->belongs_to(user => 'Registry::User::Schema::Result::User', 'user_id');


=head2 sqlt_deploy_hook
  Description: Add relevant missing indexes to the table
  Returntype : undef
  Exceptions : none
  Caller     : general

=cut

sub sqlt_deploy_hook {
  my ($self, $sqlt_table) = @_;

  # Composite primary key only provides indexing from user to role, not role to user
  $sqlt_table->add_index(name => 'reverse_idx', fields => ['role_id', 'user_id']);

  return;
}


1;
