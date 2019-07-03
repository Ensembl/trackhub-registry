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

package Registry::User::Schema::Result::Role;
use strict;
use warnings;
use parent qw/DBIx::Class::Core/;

__PACKAGE__->table('roles');
__PACKAGE__->add_columns(
  role_id => {
    data_type => 'int',
    is_nullable => 0,
    is_auto_increment => 1
  },
  name => {
    data_type => 'varchar',
    is_nullable => 0,
  }
);

__PACKAGE__->set_primary_key('role_id');

__PACKAGE__->has_many( user_roles => 'Registry::User::Schema::Result::UserRole', 'role_id');
__PACKAGE__->many_to_many( users => 'user_roles', 'user');


=head2 sqlt_deploy_hook
  Description: Add relevant indexes to the table
  Returntype : undef
  Exceptions : none
  Caller     : general

=cut

sub sqlt_deploy_hook {
  my ($self, $sqlt_table) = @_;

  $sqlt_table->add_index(name => 'name_idx', fields => ['name', 'role_id']);
  return;
}

1;
