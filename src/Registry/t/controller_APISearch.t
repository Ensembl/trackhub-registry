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
use JSON;
use HTTP::Request::Common qw/GET POST/;
use LWP::Simple;
use Registry::Utils; # slurp_file
use Registry::User::TestDB;
use Digest;
use Test::WWW::Mechanize::Catalyst;
use Search::Elasticsearch;

BEGIN {
  use FindBin qw/$Bin/;
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}
my $INDEX_NAME = 'trackhubs'; # Matches registry_testing.conf
my $INDEX_TYPE = 'trackdb';


# my $db = Registry::User::TestDB->new(
#   config => {
#     driver => 'SQLite',
#     file => './thr_users.db', # This has to match registry_testing.conf db name
#     create => 1
#   },
# );
# # Make a test user for the application
# my $digest = Digest->new('SHA-256');
# my $salt = 'afs]dt42!'; # This has to match registry_testing.conf pre_salt

# $digest->add($salt);
# $digest->add('password');

# my $user = $db->schema->resultset('User')->create({
#   username => 'test-dude',
#   password => $digest->b64digest,
#   email => 'test@home',
#   continuous_alert => 1
# });
# $user->add_to_roles({ name => 'user' });

# Make a hub that belongs to this user

my $es_nodes = '127.0.0.1:9200';
my $es_client = Search::Elasticsearch->new(
  nodes => $es_nodes
);
ok ($es_client->cluster->health, 'ES server waiting');

my $hub_content = decode_json(Registry::Utils::slurp_file("$Bin/track_hub/plant1.json"));
$hub_content->{public} = JSON::true;
$hub_content->{owner} = 'test-dude';

$es_client->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => $hub_content
);
$es_client->indices->refresh;

# Begin the testing!
use Catalyst::Test 'Registry';
note 'Test catalyst server up';

# my $request = HTTP::Request::Common::GET('http://127.0.0.1/api/login');
# $request->authorization_basic('test-dude', 'password');
my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');

# $mech->get_ok('http://127.0.0.1/');

# $mech->request($request); # Can't seem to get non-form authentication to work

# cmp_ok ($mech->status, '==', 200, 'Authentication achieved');
# ok(my $response = $mech->response, 'Request to log in');
# ok($response->is_success, 'Login happened');
# my $content = from_json($response->content);
# ok(exists $content->{auth_token}, 'Log in includes an auth_token we can use in the API');
# my $auth_token = $content->{auth_token};

# # Host a fake hub on localhost that we can submit

# my $fake_server = Test::HTTP::MockServer->new();
# my $fake_response = sub {
#   my ($request, $response) = @_;
#   $response->code(200);
#   if ($request->uri =~ m/hub.txt/ ) {
#     $response->content(Registry::Utils::slurp_file("$Bin/track_hub/test_hub_1/hub.txt"));
#   } elsif ($request->uri =~ m/genomes.txt/) {
#     $response->content(Registry::Utils::slurp_file("$Bin/track_hub/test_hub_1/genomes.txt"));
#   } elsif ($request->uri =~ m/trackdb/) {
#     $response->content(Registry::Utils::slurp_file("$Bin/track_hub/test_hub_1/grch38/trackDb.txt"));
#   }
# };
# $fake_server->start_mock_server($fake_response);

# # Submit a new hub
# my $hub_port = $fake_server->port(); # port is randomised on start, so we have to keep any eye on it

# $mech->add_header( user => 'test-dude', 'auth-token' => $auth_token);
# $mech->post_ok(
#   "http://localhost/api/trackhub/?permissive=1",
#   { 
#     content => to_json({
#       url => "http://localhost:$hub_port/hub.txt",
#       assemblies => 'GRCh38',
#       public => 1 # technically not required, but explicit here
#     })
#   },
#   'Submit new trackhub using authentication token'
# );

# One hub is already registered during test setup, we try to submit it again

# # Now register another hub but do not make it available for search
# note sprintf "Submitting hub ultracons (not searchable)";
# $request = POST('/api/trackhub?permissive=1',
#     'Content-type' => 'application/json',
#     'Content'      => to_json({ url => 'http://genome-test.gi.ucsc.edu/~hiram/hubs/GillBejerano/hub.txt', public => 0 }));
# $request->headers->header(user       => 'trackhub1');
# $request->headers->header(auth_token => $auth_token);
# ok($response = request($request), 'POST request to /api/trackhub');
# ok($response->is_success, 'Request successful 2xx');
# is($response->content_type, 'application/json', 'JSON content type');

# # Logout
# $request = GET('/api/logout');
# $request->headers->header(user       => 'trackhub1');
# $request->headers->header(auth_token => $auth_token);
# ok($response = request($request), 'GET request to /api/logout');
# ok($response->is_success, 'Request successful 2xx');

#
# /api/search endpoint
#
# no data

$mech->add_header('Content-type' => 'application/json');
$mech->post('/api/search/', content => undef); # i.e. no query for the server to use

is($mech->response->code, 400, 'Request with no body unsuccessful');
my $content = from_json($mech->response->content);
like($content->{error}, qr/Missing/, 'Correct error response');

# empty query, get all entries
# default page and entries_per_page

my $message = to_json({ query => '' });

$mech->post('/api/search/', content => $message );

ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');

$content = from_json($mech->response->content);
is($content->{total_entries}, 1, 'There is one public hub and it is matched by a blanket query');
is($content->{items}[0]{hub}{shortLabel}, 'Plants', 'The results contains some real content');

# Now let's add another hub or two

$hub_content = decode_json(Registry::Utils::slurp_file("$Bin/track_hub/plant2.json"));
$hub_content->{public} = JSON::true;
$hub_content->{owner} = 'test-dude';

$es_client->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => $hub_content
);

$hub_content = decode_json(Registry::Utils::slurp_file("$Bin/track_hub/plant3.json"));
$hub_content->{public} = JSON::true;
$hub_content->{owner} = 'test-dude';

$es_client->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => $hub_content
);

$es_client->indices->refresh;

# Try open query again

$mech->post('/api/search/', content => $message );

ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');

$content = from_json($mech->response->content);
is($content->{total_entries}, 3, 'Two more hubs added to the original');

# What if we limit the number on the page?
$mech->post('/api/search/?entries_per_page=1&page=1', content => $message );
ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');
$content = from_json($mech->response->content);
is($content->{total_entries}, 3, 'Three hubs available');
is(scalar @{ $content->{items} }, 1, 'Only one is on this page');

# Test getting the n-th page
$mech->post('/api/search/?entries_per_page=1&page=3', content => $message );
ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');
$content = from_json($mech->response->content);
is(scalar @{$content->{items}}, 1, 'Number of search results per page beyond end of results');

# option to return all results
$mech->post('/api/search/?all=1', content => $message );
ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');
$content = from_json($mech->response->content);
is($content->{total_entries}, 3, 'Number of search results');
is(scalar @{$content->{items}}, 3, 'All three returned');

# asking for all results defeats pagination parameters
$mech->post('/api/search/?all=1&entries_per_page=1&page=2', content => $message );
ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');
$content = from_json($mech->response->content);
is($content->{total_entries}, 3, 'Number of search results');
is(scalar @{$content->{items}}, 3, 'All three returned');


$mech->post('/api/search/?page=2', content => to_json({ query => 'neutrophil' }) );
ok($mech->success, 'Request successful');
is($mech->response->content_type, 'application/json', 'JSON content type');
$content = from_json($mech->response->content);
is($content->{total_entries}, 0, 'No hits for deliberately weird query');
is(scalar @{$content->{items}}, 0, 'Nothing in the items from a no-hit query');


# Test the unpublicised endpoint for trackhub metadata miners
$mech->get('/api/search/all');
ok($mech->success, 'Endpoint responds positively');
is($mech->response->content_type, 'application/json', 'JSON content type');
$content = from_json($mech->response->content);

cmp_ok(@$content, '==', 3, 'All hubs retrieved via /api/search/all');
# Returned order is random, so we must sort the results first to make testing reliable
my @order_hits = sort { $a->{_source}{species}{scientific_name} cmp $b->{_source}{species}{scientific_name}} @$content;
is( $order_hits[0]->{_source}{species}{scientific_name}, 'Arabidopsis thaliana', 'First response is always the same');
is( $order_hits[-1]->{_source}{species}{scientific_name}, 'Ricinus communis', 'Last response is also always the same');

$es_client->indices->delete(index => $INDEX_NAME);

done_testing();
