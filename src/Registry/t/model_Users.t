# Copyright [2015-2018] EMBL-European Bioinformatics Institute
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
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

# use Registry;
use Registry::Utils; # slurp_file, es_running
use Registry::User::TestDB;

my $db = Registry::User::TestDB->new(
  config => {
    driver => 'SQLite',
    file => 'thr_users.db',
    create => 1
  },
);
$db->schema; # Force a lazy DB create so that $db->dsn gets populated

use_ok 'Registry::Model::Users';

my $model = Registry::Model::Users->new(
  # This should come from server config outside of model testing
  connect_info => { dsn => $db->dsn }
);

my $admin_user = $model->schema->resultset('User')->create({
  username => 'admin',
  first_name => 'Rooty',
  last_name => 'McRootFace',
  email => 'dev@null',
  password => 'god',
  continuous_alert => 0,
  affiliation => 'you'
});
$admin_user->add_to_roles({ name => 'user'});
$admin_user->add_to_roles({ name => 'admin'});

my $sacrificial_user = $model->schema->resultset('User')->create({
  username => 'sacrifice',
  first_name => 'Dr',
  last_name => 'Doomed',
  email => 'dev@null',
  password => 'help',
  continuous_alert => 0,
  affiliation => 'The void'
});
$sacrificial_user->add_to_roles({ name => 'user'});


my $user_copy = $model->get_user('admin');
is($user_copy->username,'admin','Test user can be fetched by username');
my $id = $user_copy->id;
my $username = $model->get_user_by_id($id);
is($username,$user_copy->username,'Same username ID retrieved');

$user_copy = $model->get_user('gerbil');
ok(! defined $user_copy, 'Try getting a non-existing user');

$username = $model->get_user_by_id(500000);
ok(! defined $username, 'Try getting a non-existing user');

my $users = $model->get_all_users;

cmp_ok(scalar @$users, '==', 2, 'All (two) test users fetched at once, including administrator');
is_deeply([sort map { $_->username } @$users],[qw/admin sacrifice/], 'All (two) test users fetched at once, including administrator');

$model->delete_user($sacrificial_user);
$users = $model->get_all_users();
cmp_ok(scalar @$users, '==', 1, 'Total user count has decreased');
is($users->[0]->username, 'admin', 'sacrifice has been deleted');

# Check for regression with non-boolean continuous_alert property

$admin_user->continuous_alert(1);

$admin_user->update;
$user_copy = $model->get_user('admin');
cmp_ok($user_copy->continuous_alert, '==', 1, 'Continuous alert property is set as a number, stored as boolean, and then used as a number again');

done_testing();