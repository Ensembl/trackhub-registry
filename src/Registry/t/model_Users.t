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
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

use JSON;
use Registry;
use Registry::Utils; # slurp_file, es_running
use Registry::Indexer;

use_ok 'Registry::Model::Users';

my $es = Registry::Model::Users->new();

my $config = Registry->config()->{'Model::Search'};

my $indexer = Registry::Indexer->new(
  dir   => "$Bin/trackhub-examples/",
  trackhub => {
    index => $config->{trackhub}{index},
    type  => $config->{trackhub}{type},
    mapping => 'trackhub_mappings.json'
  },
  authentication => {
    index => $config->{user}{index},
    type  => $config->{user}{type},
    mapping => 'authentication_mappings.json'
  }
);

$indexer->index_users();
$indexer->index_trackhubs();

my $hit = $es->get_user('trackhub1');
is($hit->{username},'trackhub1','Test user can be fetched by username');
my $id = $hit->{id};
$hit = $es->get_user_by_id($id);
is($hit,'trackhub1','Same user doc retrieved using ID as username');

$hit = $es->get_user('gerbil');
ok(! defined $hit, 'Try getting a non-existing user');

$hit = $es->get_user_by_id(500000);
ok(! defined $hit, 'Try getting a non-existing user');

my $users = $es->get_all_users;

cmp_ok(scalar @$users, '==', 4, 'All four test users fetched at once, including administrator');
is_deeply([sort map { $_->{username} } @$users],[qw/admin trackhub1 trackhub2 trackhub3/], 'All three test users fetched at once, including administrator');

my ($backup) = grep { $_->{username} eq 'trackhub3'} @$users; # Save a copy of trackhub3

$es->delete_user($backup->{id});
$users = $es->get_all_users();
cmp_ok(scalar @$users, '==', 3, 'Total user count has decreased');
is_deeply([sort map { $_->{username} } @{ $users }], [qw/admin trackhub1 trackhub2/] , 'trackhub3 has been deleted');

# Now put trackhub3 back
$id = $es->generate_new_user_id;
note "New ID = $id\n";
$es->update_profile($id, $backup);
is_deeply([qw/admin trackhub1 trackhub2 trackhub3/] ,[sort map { $_->{username} } @{$es->get_all_users}], 'trackhub3 has been reinstated');

# Check for regression with non-boolean continuous_alert property
$backup->{continuous_alert} = 1;
$es->update_profile($id, $backup);
$hit = $es->get_user('trackhub3');
cmp_ok($hit->{continuous_alert}, '==', 1, 'Continuous alert property is set as a number, stored as boolean, and then used as a number again');


done_testing();