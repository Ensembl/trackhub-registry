# Copyright [2015-2022] EMBL-European Bioinformatics Institute
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


my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');

#
# /api/search endpoint
#

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
