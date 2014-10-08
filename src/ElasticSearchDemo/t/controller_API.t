use strict;
use warnings;
use Test::More;
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use JSON;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;

use Catalyst::Test 'ElasticSearchDemo';

use ElasticSearchDemo::Utils; # es_running, slurp_file
use ElasticSearchDemo::Indexer; # index a couple of sample documents

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    96 unless &ElasticSearchDemo::Utils::es_running();

  # index test data
  note 'Preparing data for test (indexing sample documents)';
  my $indexer = ElasticSearchDemo::Indexer->new(dir   => "$Bin/../../../docs/trackhub-schema/draft02/examples/",
						index => 'test',
						type  => 'trackhub',
						mapping => 'trackhub_mappings.json');
  $indexer->index();

  #
  # Requests with no authentication fail.
  # Should log in first
  #
  my @endpoints = 
    (
     ['/api/trackhub', 'GET', 'Return the list of available docs'],
     ['/api/trackhub/create', 'PUT', 'Create new trackhub document'],
     ['/api/trackhub/1', 'GET', 'Return content for a document with the specified ID'],
     ['/api/trackhub/1', 'POST', 'Update content for a document with the specified ID'],
     ['/api/trackhub/1', 'DELETE', 'Delete document with the specified ID']
    );
  foreach my $ep (@endpoints) {
    my ($endpoint, $method) = ($ep->[0], $ep->[1]);
    my $request;
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):($method eq 'PUT'?PUT($endpoint):DELETE($endpoint)));
    ok(my $response = request($request), "Unauthorized $method request to $endpoint");
    is($response->code, 401, 'Unauthorized response 401');
    like($response->content, qr/You need to login, get an auth_token/, 'Unauthorized response content');
  }

  #
  # Authenticate
  #
  my $request = GET('/api/login');
  $request->headers->authorization_basic('test', 'test');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  #
  # Requests to endpoints with no or partial (use just user) API-key based authentication
  #
  foreach my $ep (@endpoints) {
    my ($endpoint, $method) = ($ep->[0], $ep->[1]);
    my $request;
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):($method eq 'PUT'?PUT($endpoint):DELETE($endpoint)));
    $request->headers->header(user => 'test');
    ok(my $response = request($request), "Unauthorized request to $endpoint");
    is($response->code, 401, 'Unauthorized response 401');
    like($response->content, qr/You need to login, get an auth_token/, 'Unauthorized response content');
  }

  #
  # Authenticated requests (using API-key)
  #
  # /api (GET): returns the list of endpoints (name/method/description)
  #
  $request = GET('/api');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'text/html', 'HTML Content-type');
  map { like($response->content, qr/$_->[2]/, sprintf "Contains endpoint %s description", $_->[0]) } @endpoints;
  
  #
  # /api/trackhub (GET): get list of documents with their URIs
  #
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "Contains correct resource (document) URI") } 1 .. 2;
  
  #
  # /api/trackhub/:id (GET)
  #
  # request correct document
  $request = GET('/api/trackhub/1');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET Request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{data}}, 1, 'One trackhub');
  is($content->{data}[0]{name}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Trackhub name');
  is($content->{configuration}{bpDnaseRegionsC0010K46DNaseEBI}{bigDataUrl}, 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Trackhub url');

  # request incorrect document
  $request = GET('/api/trackhub/3');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub/3');
  is($response->code, 404, 'Request unsuccessful 404');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  #
  # /api/trackhub/:id (POST) update document
  #
  # request incorrect document
  $request = POST('/api/trackhub/3',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not exist/, 'Correct error response');

  # request to update a doc but do not supply data
  $request = POST('/api/trackhub/1',
  		 'Content-type' => 'application/json');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/1');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');

  # update doc1
  $request = POST('/api/trackhub/1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ test => 'test' }));
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/1');
  ok($response->is_success, 'Doc update request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{test}, 'test', 'Correct updated content');

  #
  # /api/trackhub/:id (DELETE) delete document
  #
  # request incorrect document
  $request = DELETE('/api/trackhub/3');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackhub/3');
  is($response->code, 404, 'Request unsuccessful 404');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  # delete doc1
  $request = DELETE('/api/trackhub/1');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  $content = from_json($response->content);
  is($content->{test}, 'test', 'Content of deleted resource');

  # request for deleted doc should fail
  $request = GET('/api/trackhub/1');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub/1');
  is($response->code, 404, 'Request unsuccessful 404');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  note "Re-creating index test";
  $indexer->create_index(); # do not index this time through the indexer, the API will do that

  #
  # /api/trackhub/create (PUT): create new document
  #
  # request to create a doc but do not supply data
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');
  
  # now the index's empty, create the sample docs through the API
  my $docs = $indexer->docs;

  #
  # TODO: should test content of created docs
  #
  # create doc1
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => &ElasticSearchDemo::Utils::slurp_file($docs->{1}));
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackhub\/1/, 'Correct URI for created doc');
  # create doc2
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => &ElasticSearchDemo::Utils::slurp_file($docs->{2}));
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackhub\/2/, 'Correct URI for created doc');
  
  # POST request should fail
  $request = POST('/api/trackhub/create',
  		  'Content-type' => 'application/json',
  		  'Content'      => &ElasticSearchDemo::Utils::slurp_file($docs->{2}));
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create');
  ok(!$response->is_success, 'Doc create POST request unsuccessful');
  is($response->code, 405, 'Method not allowed');

  # should now have two documents which we can access
  # via the /api/trackhub endpoint
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'test');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "Contains correct resource (document) URI") } 1 .. 2;

}

done_testing();
