use strict;
use warnings;
use Test::More;
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;

use Catalyst::Test 'Registry';

use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    225 unless &Registry::Utils::es_running();

  # index test data
  note 'Preparing data for test (indexing sample documents)';
  my $config = Registry->config()->{'Model::Search'};
  my $indexer = Registry::Indexer->new(dir   => "$Bin/trackhub-examples/",
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
  $indexer->index_trackhubs();
  $indexer->index_users();

  #
  # Authenticate
  #
  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  use Data::Dumper;
  print Dumper $request;
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};
  
  #
  # /api/trackdb (GET): get list of documents with their URIs
  #
  $request = GET('/api/trackdb');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  print Dumper $request;

  ok($response = request($request), 'GET request to /api/trackdb');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 2, "Number of trackhub1 docs");
  map { like($content->{$_}, qr/api\/trackdb\/$_/, "Contains correct resource (document) URI") } 1 .. 2;

  # request to update doc with invalid content (non v1.0 compliant)
  $request = PUT('/api/trackdb/1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ test => 'test' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  print Dumper $request;
}

done_testing();
