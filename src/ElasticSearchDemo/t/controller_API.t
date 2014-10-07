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
    79 unless &ElasticSearchDemo::Utils::es_running();

  # index test data
  note 'Preparing data for test (indexing sample documents)';
  my $indexer = ElasticSearchDemo::Indexer->new(dir   => "$Bin/../../../docs/trackhub-schema/draft02/examples/",
						index => 'test',
						type  => 'trackhub',
						mapping => 'trackhub_mappings.json');
  $indexer->index();

  #
  # Requests with no authentication fail
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
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):DELETE($endpoint));
    ok(my $response = request($request), "Unauthorized request to $endpoint");
    is($response->code, 401, 'Unauthorized response 401');
    like($response->content, qr/Authorization required/, 'Unauthorized response content');
  }

  #
  # /api (GET): returns the list of endpoints (name/method/description)
  #
  my $request = GET('/api');
  $request->headers->authorization_basic('test', 'test');
  ok(my $response = request($request), 'GET request to /api');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'text/html', 'HTML Content-type');
  map { like($response->content, qr/$_->[2]/, sprintf "Contains endpoint %s description", $_->[0]) } @endpoints;
  
  #
  # /api/trackhub (GET): get list of documents with their URIs
  #
  $request = GET('/api/trackhub');
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "Contains correct resource (document) URI") } 1 .. 2;
  
  #
  # /api/trackhub/:id (GET)
  #
  # request correct document
  $request = GET('/api/trackhub/1');
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'GET Request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{data}}, 1, 'One trackhub');
  is($content->{data}[0]{name}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Trackhub name');
  is($content->{configuration}{bpDnaseRegionsC0010K46DNaseEBI}{bigDataUrl}, 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Trackhub url');

  # request incorrect document
  $request = GET('/api/trackhub/3');
  $request->headers->authorization_basic('test', 'test');
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
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'POST request to /api/trackhub/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not exist/, 'Correct error response');

  # request to update a doc but do not supply data
  $request = POST('/api/trackhub/1',
  		 'Content-type' => 'application/json');
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'POST request to /api/trackhub/1');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');

  # update doc1
  $request = POST('/api/trackhub/1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ test => 'test' }));
  $request->headers->authorization_basic('test', 'test');
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
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'DELETE request to /api/trackhub/3');
  is($response->code, 404, 'Request unsuccessful 404');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  # delete doc1
  $request = DELETE('/api/trackhub/1');
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'DELETE request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  $content = from_json($response->content);
  is($content->{test}, 'test', 'Content of deleted resource');

  # request for deleted doc should fail
  $request = GET('/api/trackhub/1');
  $request->headers->authorization_basic('test', 'test');
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
  $request->headers->authorization_basic('test', 'test');
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
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackhub\/1/, 'Correct URI for created doc');
  # create doc2
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => &ElasticSearchDemo::Utils::slurp_file($docs->{2}));
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackhub\/2/, 'Correct URI for created doc');
  
  # POST request should fail
  $request = POST('/api/trackhub/create',
  		  'Content-type' => 'application/json',
  		  'Content'      => &ElasticSearchDemo::Utils::slurp_file($docs->{2}));
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'POST request to /api/trackhub/create');
  ok(!$response->is_success, 'Doc create POST request unsuccessful');
  is($response->code, 405, 'Method not allowed');

  # should now have two documents which we can access
  # via the /api/trackhub endpoint
  $request = GET('/api/trackhub');
  $request->headers->authorization_basic('test', 'test');
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "Contains correct resource (document) URI") } 1 .. 2;

}



# #
# # TODO: check status codes
# #
# # request subroutine return is HTTP::Response object with attribs:
# #  _content
# #  _rc
# #  _headers
# #  _msg
# #  _request
# #
# my $response = request('/api');
# ok( !$response->is_success, 'Request with no credentials should not succeed' );

# my $content = from_json($response->content); 
# is( $content->{data}{error}, "Please specify username/password credentials", "Error response: no credentials");

# $response = request('/api?username=pippo;password=pluto');
# ok( !$response->is_success, 'Request with incorrect credentials should not succeed' );
# $content = from_json($response->content); 
# is( $content->{data}{error}, "Unauthorized", "Unsuccessful authentication message");

# $response = request('/api?username=test;password=test');
# ok( $response->is_success, 'Request with correct credentials should succeed' );
# $content = from_json($response->content); 
# is( $content->{data}{msg}, "Welcome user test", "Successful authentication message");


# this one gets the JSON string
# $response = get '/api';
# print ref $response, "\n";

# ##########
# # Test initial gift list includes all the gifts
# #
# my @all_data = MyGifts::Model::Gifts->new->_get_data;
 
# my $response = get '/gifts';
 
# my @gifts = @{from_json($response)->{data}};
# is(@gifts, @all_data, "gift count match");
 
# for ( my $i=0 ; $i < @all_data; $i++ ) {
#   is(keys %{$gifts[$i]}, 2, "[$i] has 2 data fields");
#   is($gifts[$i]->{name}, $all_data[$i]->{name}, "[$i] name match");
#   is($gifts[$i]->{id}, $all_data[$i]->{id}, "[$i] id match");
# }

# my $response = get '/api';
# print $response;
# print Dumper(request('/api')), "\n\n";

done_testing();
