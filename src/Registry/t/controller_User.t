# Copyright [2015-2016] EMBL-European Bioinformatics Institute
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

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

use Catalyst::Test 'Registry';
use Registry::Utils;
use Registry::Indexer;

use_ok 'Registry::Controller::User';
BEGIN { use_ok("Test::WWW::Mechanize::Catalyst" => "Registry") }

my $config = Registry->config()->{'Model::Search'};
my $indexer = Registry::Indexer->new(dir   => "$Bin/trackhub-examples/",
						trackhub => {
						  index => $config->{trackhub}{index},
						  type  => $config->{trackhub}{type},
						  mapping => 'trackhub_mappings.json'
						}
       );

$indexer->index_trackhubs();
    
# Create two 'user agents' to simulate two different users ('trackhub1' & 'trackhub2')
my $ua1 = Test::WWW::Mechanize::Catalyst->new;
my $ua2 = Test::WWW::Mechanize::Catalyst->new;


# Use a simplified for loop to do tests that are common to both users
# Use get_ok() to make sure we can hit the base URL
# Second arg = optional description of test (will be displayed for failed tests)
# Note that in test scripts you send everything to 'http://localhost'
$_->get_ok("http://localhost/", "Check redirect of base URL") for $ua1, $ua2;

# Use title_is() to check the contents of the <title>...</title> tags
$_->title_is("The Track Hub Registry", "Check for The Track Hub Registry title") for $ua1, $ua2;

$_->get_ok("http://localhost/login", "Check redirect of login URL") for $ua1, $ua2;

# Log in as ua1 with wrong password
$ua1->submit_form(
  form_number => 2,
  fields => {
  username => 'test01',
  password => 'test02',
  });
$ua1->content_contains("Wrong username or password", "Page contains - Wrong username or password");

# Log in as ua1 with right password
$ua1->submit_form(
  form_number => 2,
  fields => {
  username => 'test01',
  password => 'test01',
  });
$ua1->content_contains("Your track collections", "Page contains - Your track collections");



#Try to register a new user
$ua1->get_ok("http://localhost/logout", "Check you have logged out");

$ua1->get_ok("http://localhost/user/register", "Check redirect of login URL");
$ua1->content_contains("Register as track hub provider", "Page contains - Register as track hub provider");

#Try with already existing user name
$ua1->submit_form(
  form_number => 2,
  fields => {
  		first_name => 'Test First',
  		last_name => 'Test Last',
  		affiliation => 'EMBL-EBI',
  		email => 'testuser@ebi.ac.uk',
	  	username => 'test01',
  		password => 'test1234',
  		password_conf => 'test1234',
  		check_interval => 0,
  		continuous_alert => 1
   });
$ua1->content_contains("User test01 already exists. Please choose a different username", "Page contains - User test01 already exists");


#Try with wrong email format
$ua1->submit_form(
  form_number => 2,
  fields => {
  		first_name => 'Test First',
  		last_name => 'Test Last',
  		affiliation => 'EMBL-EBI',
  		email => 'testuser',
	  	username => 'test01',
  		password => 'test1234',
  		password_conf => 'test1234',
  		check_interval => 0,
  		continuous_alert => 1
   });
$ua1->content_contains("Email should be of the format someuser\@example.com", "Page contains - Email should be of the format someuser\@example.com");

#Try with wrong email format
$ua1->submit_form(
  form_number => 2,
  fields => {
  		first_name => 'Test First',
  		last_name => 'Test Last',
  		affiliation => 'EMBL-EBI',
  		email => 'testuser@test.com',
	  	username => 'test03',
  		password => 'test1234',
  		password_conf => 'test1234',
  		check_interval => 0,
  		continuous_alert => 1
   });

$ua1->get_ok("http://localhost/user/test03/list_trackhubs", "Go to list_trackhubs");  
$ua1->content_contains("Your track collections", "Page contains - Your track collections");

#Logout
$ua1->get_ok("http://localhost/logout", "Check you have logged out");

#Login as admin
$ua1->get_ok("http://localhost/login", "Check redirect of login URL");

$ua1->submit_form(
  form_number => 2,
  fields => {
  username => 'admin',
  password => 'dummy',
  });

$ua1->content_contains("TrackHub Providers", "Page contains - TrackHub Providers");
$ua1->get_ok("http://localhost/user/admin/list_providers", "Go to list providers");
$ua1->content_contains("test03", "Page contains - new user test03");

system("sqlite3 registry.db 'delete from users where username=\"test03\"' ");

$ua1->get_ok("http://localhost/user/admin/list_providers", "Go to list providers");
$ua1->content_lacks("test03", "Page do not contain user test03");

#Logout
$ua1->get_ok("http://localhost/logout", "Check you have logged out");

done_testing();

