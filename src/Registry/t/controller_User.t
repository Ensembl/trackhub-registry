# Copyright [2015-2020] EMBL-European Bioinformatics Institute
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
use Test::WWW::Mechanize::Catalyst;
use Digest;
use HTTP::Request::Common;
use Search::Elasticsearch::TestServer;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

### Set up test schema and users ###
use Registry::User::TestDB;

my $db = Registry::User::TestDB->new(
  config => {
    driver => 'SQLite',
    file => './thr_users.db', # This has to match registry_testing.conf db name
    create => 1
  },
);

my $digest = Digest->new('SHA-256');
my $salt = 'afs]dt42!'; # This has to match registry_testing.conf pre_salt

$digest->add($salt);
$digest->add('rule brittania');

my $user = $db->schema->resultset('User')->create({
  username => 'rodney',
  password => $digest->b64digest,
  email => 'a@b',
  continuous_alert => 1
});
$user->add_to_roles({ name => 'user' });

$digest = Digest->new('SHA-256');
$digest->add($salt);
$digest->add('reichstag');
my $admin_user = $db->schema->resultset('User')->create({
  username => 'gneisenau',
  password => $digest->b64digest,
  email => 'b@a',
  continuous_alert => 1
});
$admin_user->add_to_roles({ name => 'user' });
$admin_user->add_to_roles({ name => 'admin' });

use Catalyst::Test 'Registry';

### Requires ES running in the background on 127.0.0.1:9200

### Test user login and management interface ###

use_ok 'Registry::Controller::User';

my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');
$mech->get_ok('/'); # Homepage ready

# Can't use this functionality, webpage uses HTML5 features
# $mech->html_lint_ok('Homepage is valid HTML');
$mech->title_is('The Track Hub Registry');
$mech->content_contains('Login','A login option is available');

# Now log in
$mech->get_ok('/login', 'Navigate to login dialogue');

# Make an erroneous login attempt

$mech->submit_form(
  form_id => 'login_form',
  fields => {
    username => 'nobody',
    password => 'ha'
  }
);
# This mechanism for logging in is bad. These forms should at least try to obfuscate the credentials
$mech->base_is('http://localhost/login', 'Ended up back on the login screen');
$mech->content_contains('Incorrect user name or password', 'Login failure message present');

# We should be back at the login screen, unless the previous failure has not redirected correctly
$mech->submit_form(
  form_id => 'login_form',
  fields => {
    username => $user->username,
    password => 'bad password'
  }
);
$mech->base_is('http://localhost/login', 'Ended up back on the login screen');
$mech->content_contains('Incorrect user name or password', 'Login failure message present');

# Make a real login attempt
$mech->submit_form_ok(
  {
    form_id => 'login_form',
    fields => {
      username => $user->username,
      password => 'rule brittania'
    }
  },
  'Log non-admin user in'
);

# Can't check URL here for opaque reasons
$mech->content_contains('Your track collections', 'Did we navigate to default user hub listing?');

# Check user profile page
$mech->get_ok('/user/profile');
$mech->content_contains('Profile for user', 'Profile header present');

# Update affiliation (can't see a way to use the auto-populated fields)
$mech->submit_form_ok(
  {
    form_id => 'profile_form',
    fields => {
      username => $user->username,
      password => 'rule brittania',
      password_conf => 'rule brittania',
      affiliation => 'atlantic fleet'
    }
  }
);

$mech->content_contains('atlantic fleet', 'Affiliation is shown in the profile form');
# Could also check the DB I suppose.

$mech->get('/user/delete/gneisenau');
# Not easy to tell if the delete suceeded or not, but we can log in as the other user

$mech->get_ok('/logout', 'User logs out');
$mech->base_is('http://localhost/', 'Back at home page');

$mech->get_ok('/login', 'Go back to login page');
$mech->submit_form_ok(
  {
    form_id => 'login_form',
    fields => {
      username => $admin_user->username,
      password => 'reichstag'
    }
  },
  'Log admin user in'
);
$mech->content_contains('Your track collections', 'Looking at admin-owned hubs');

# Use admin powers to inspect listed users:

$mech->get_ok('/user/providers', 'Navigate to admin-viewable list of hub submitters');
$mech->content_contains('rodney', 'rodney is in the results');



done_testing();
