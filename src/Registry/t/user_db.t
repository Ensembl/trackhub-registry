# Copyright [2015-2019] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;
use Test::More;

use Registry::User::TestDB;

my $test_db = Registry::User::TestDB->new(
  config => {
    driver => 'SQLite',
    file   => './test.db'
  }
);

my $schema = $test_db->schema;
my $role = $schema->resultset('Role')->find({ name => 'admin'});

is ($role->name, 'admin', 'Admin role auto-created in user DB');


my $user = $schema->resultset('User')->create({
  username => 'andy',
  first_name => 'Andy',
  last_name => 'McBeer',
  email => 'be@eeeer',
  password => 'homebrew',
  continuous_alert => 0,
  affiliation => 'nuffin'
});
$user->add_to_roles({ name => 'user'});

my ($pointer_to_user) = $role->users->all(); # Look for admin people

ok(!$pointer_to_user, 'No hits for admin users');

my $admin_user = $schema->resultset('User')->create({
  username => 'admin',
  first_name => 'Rooty',
  last_name => 'McRootFace',
  email => 'dev@null',
  password => 'god',
  continuous_alert => 0,
  affiliation => 'you'
});

$admin_user->add_to_roles({ name => 'admin' });
$admin_user->add_to_roles({ name => 'user' });

$role = $schema->resultset('Role')->find({ name => 'user'});

my ($user_a, $user_b) = $role->users->all(); # Look for users (including admins)

is($user_a->username, 'andy','Check we can fetch all users with user role from DB');
is($user_b->username, 'admin','Check we can fetch all users with user role from DB');

done_testing();