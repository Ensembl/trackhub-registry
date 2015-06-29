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

use Catalyst::Test 'Registry';

use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    97 unless &Registry::Utils::es_running();

  # index test data
  note 'Preparing data for test (indexing sample documents)';
  my $config = Registry->config()->{'Model::Search'};
  my $indexer = Registry::Indexer->new(dir   => "$Bin/trackhub-examples/",
						index => $config->{index},
						trackhub => {
						  type  => $config->{type}{trackhub},
						  mapping => 'trackhub_mappings.json'
						},
						authentication => {
						  type  => $config->{type}{user},
						  mapping => 'authentication_mappings.json'
						}
					       );
  $indexer->index_trackhubs();
  $indexer->index_users();

  #
  # Requests with no authentication should fail.
  # Should log in first
  #
  my @endpoints = 
    (
     ['/api/trackhub', 'GET', 'Return the list of available docs'],
     ['/api/trackhub/create', 'PUT', 'Create new trackhub document'],
     # the following docs belong to user trackhub2, as set by the Indexer
     ['/api/trackhub/3', 'GET', 'Return content for a document with the specified ID'],
     ['/api/trackhub/3', 'POST', 'Update content for a document with the specified ID'],
     ['/api/trackhub/3', 'DELETE', 'Delete document with the specified ID']
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
  # Authentication: login and get an auth token
  #
  # 1. incorrect username
  my $request = GET('/api/login');
  $request->headers->authorization_basic('test', 'test');
  ok(my $response = request($request), 'Request to log in with incorrect username/password');
  is($response->code, 401, 'Log in request unsuccessful 401');
  is($response->content_type, 'text/plain', 'Text content type');
  like($response->content, qr/Authorization required/, 'Unauthorized response content');
  #
  # 2. correct username, incorrect password
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'test');
  ok($response = request($request), 'Request to log in with correct username, incorrect password');
  is($response->code, 401, 'Log in request unsuccessful 401');
  is($response->content_type, 'text/plain', 'Text content type');
  like($response->content, qr/Authorization required/, 'Unauthorized response content');
  #
  # 3. correct username/password, test all available users
  $request = GET('/api/login');
  my $auth_token;
  foreach my $user (qw/admin trackhub1 trackhub2/) {
    #
    # NOTE: assume same username/password set by Indexer module
    #
    my $pass = $user;
    $request->headers->authorization_basic($user, $pass);
    ok($response = request($request), 'Request to log in with correct username/password');
    ok($response->is_success, 'Log in request successful 2xx');
    is($response->content_type, 'application/json', 'JSON content type');
    my $content = from_json($response->content);
    ok(exists $content->{auth_token}, 'Logged in, got auth token');
    $auth_token = $content->{auth_token};
  }

  #
  # Requests to endpoints with incorrect/insufficient/correct 
  # information for API auth_key based authentication
  #
  # From previous test, valid user with auth_key is 'trackhub2'
  #
  # 1. incorrect username
  foreach my $ep (@endpoints) {
    my ($endpoint, $method) = ($ep->[0], $ep->[1]);
    my $request;
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):($method eq 'PUT'?PUT($endpoint):DELETE($endpoint)));
    $request->headers->header(user => 'test');
    ok(my $response = request($request), "Unauthorized request to $endpoint (no username/auth key)");
    is($response->code, 401, 'Unauthorized response 401');
    like($response->content, qr/You need to login, get an auth_token/, 'Unauthorized response content');
  }
  #
  # 2. correct username, no auth_key
  foreach my $ep (@endpoints) {
    my ($endpoint, $method) = ($ep->[0], $ep->[1]);
    my $request;
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):($method eq 'PUT'?PUT($endpoint):DELETE($endpoint)));
    $request->headers->header(user => 'trackhub2');
    ok(my $response = request($request), "Unauthorized request to $endpoint (no auth key)");
    is($response->code, 401, 'Unauthorized response 401');
    like($response->content, qr/You need to login, get an auth_token/, 'Unauthorized response content');
  }
  #
  # 3. correct username, incorrect auth_key
  foreach my $ep (@endpoints) {
    my ($endpoint, $method) = ($ep->[0], $ep->[1]);
    my $request;
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):($method eq 'PUT'?PUT($endpoint):DELETE($endpoint)));
    $request->headers->header(user => 'trackhub2');
    $request->headers->header(auth_token => 'test');
    ok(my $response = request($request), "Unauthorized request to $endpoint (correct username/incorrect auth key)");
    is($response->code, 401, 'Unauthorized response 401');
    like($response->content, qr/You need to login, get an auth_token/, 'Unauthorized response content');
  }
  #
  # 4. correct username/auth_key
  foreach my $ep (@endpoints) {
    my ($endpoint, $method) = ($ep->[0], $ep->[1]);
    my $request;
    $request = ($method eq 'GET')?GET($endpoint):($method eq 'POST'?POST($endpoint):($method eq 'PUT'?PUT($endpoint):DELETE($endpoint)));
    $request->headers->header(user => 'trackhub2');
    $request->headers->header(auth_token => $auth_token);
    ok(my $response = request($request), "Authorized request to $endpoint (correct username/auth_key)");
    is($response->content_type, 'application/json', 'JSON content type');
    my $content = from_json($response->content);
    if ($method eq 'GET' or $method eq 'DELETE') {
      ok($response->is_success, 'Request successful 2xx');
    } else { # POST/PUT
      is($response->code, 400, 'Request unsuccessful 400');
      like($content->{error}, qr/You must provide a doc/, 'Correct error response');
    } 
  }

}

done_testing();
