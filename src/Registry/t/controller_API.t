use strict;
use warnings;
use Test::More;
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
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
    212 unless &Registry::Utils::es_running();

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
     ['/api/trackdb/endpoints', 'GET', 'Return the list of available trackdb endpoints'],
     ['/api/trackdb', 'GET', 'Return the list of available trackdb docs'],
     ['/api/trackdb/create', 'PUT', 'Create new trackdb document'],
     ['/api/trackdb/create', 'POST', 'Create new trackdb documents'],
     ['/api/trackdb/1', 'GET', 'Return content for a trackdb document with the specified ID'],
     ['/api/trackdb/1', 'POST', 'Update content for a trackdb document with the specified ID'],
     ['/api/trackdb/1', 'DELETE', 'Delete trackdb document with the specified ID']
    );

  #
  # Authenticate
  #
  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  #
  # Authenticated requests (using API-key)
  #
  # /api/trackdb/endpoints (GET): returns the list of endpoints (name/method/description)
  #
  $request = GET('/api/trackdb/endpoints');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackdb/endpoints');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'text/html', 'HTML Content-type');
  map { like($response->content, qr/$_->[2]/, sprintf "Contains endpoint %s description", $_->[0]) } @endpoints;
  
  #
  # /api/trackhub (GET): get list of documents with their URIs
  #
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 2, "Number of trackhub1 docs");
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "Contains correct resource (document) URI") } 1 .. 2;
  #
  # a different user should get a different set of documents
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub2', 'trackhub2');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  $auth_token = $content->{auth_token};
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'trackhub2');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 1, "Number of trackhub2 docs");
  like($content->{3}, qr/api\/trackhub\/3/, "Contains correct resource (document) URI");
  #
  # and another user again
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub3', 'trackhub3');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  $auth_token = $content->{auth_token};
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'trackhub3');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 1, "Number of trackhub3 docs");
  like($content->{4}, qr/api\/trackhub\/4/, "Contains correct resource (document) URI");

  #
  # /api/trackhub/:id (GET)
  #
  # go back to user trackhub1 authentication
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  $auth_token = $content->{auth_token};
  #
  # request correct document
  $request = GET('/api/trackhub/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET Request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{data}}, 1, 'One trackhub');
  is($content->{data}[0]{id}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Trackhub name');
  is($content->{configuration}{bpDnaseRegionsC0010K46DNaseEBI}{bigDataUrl}, 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Trackhub url');
  #
  # request incorrect document (belongs to another provider)
  $request = GET('/api/trackhub/3');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub/3');
  is($response->code, 400, 'Request unsuccessful 400');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Cannot fetch/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $request = GET('/api/trackhub/5');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub/3');
  is($response->code, 404, 'Request unsuccessful 404');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  #
  # /api/trackhub/:id (POST) update document
  #
  # request incorrect document (belongs to another provider)
  $request = POST('/api/trackhub/3',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not belong/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $request = POST('/api/trackhub/5',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not exist/, 'Correct error response');
  
  # request to update a doc but do not supply data
  $request = POST('/api/trackhub/1',
  		 'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/1');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');

  # request to update doc with invalid content (non v1.0 compliant)
  $request = POST('/api/trackhub/1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ test => 'test' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/1');
  is($response->code, 400, 'Request unsuccessful 400');
  # the validator raises an exception with the error message, check
  $content = from_json($response->content);
  like($content->{error}, qr/Failed/, 'Correct error response');

  # update doc1
  $request = POST('/api/trackhub/1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({
					     type    => 'epigenomics',
					     hub     => { name => 'Test', shortLabel => 'Test Hub', longLabel => 'Test Hub' },
					     version => 'v1.0',
					     species => { tax_id => 9606, scientific_name => 'Homo sapiens' },
					     assembly => { accession => 'GCA_000001405.15' },
					     data => [ { id => 'test', molecule => 'genomic_DNA' } ],
					     configuration => { test => { shortLabel => 'test' } } }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/1');
  ok($response->is_success, 'Doc update request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{data}[0]{id}, 'test', 'Correct updated content');
  is($content->{owner}, 'trackhub1', 'Correct owner');

  #
  # /api/trackhub/:id (DELETE) delete document
  #
  # request incorrect document (belongs to another provider)
  $request = DELETE('/api/trackhub/3');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackhub/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not belong/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $request = DELETE('/api/trackhub/5');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackhub/5');
  is($response->code, 404, 'Request unsuccessful 404');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  # delete doc1
  $request = DELETE('/api/trackhub/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  $content = from_json($response->content);
  is($content->{species}{tax_id}, 9606, 'Content of deleted resource');

  # request for deleted doc should fail
  $request = GET('/api/trackhub/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub/1');
  is($response->code, 404, 'Request unsuccessful 404');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');


  note "Re-creating index test";
  $indexer->create_index(); # do not index the documents this time through the indexer, the API will do that
  $indexer->index_users();

  #
  # Re-Authenticate since the auth_token is deleted
  #
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  $auth_token = $content->{auth_token};

  #
  # /api/trackhub/create (PUT): create new document
  #
  # request to create a doc but do not supply data
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');
  #
  # request to create a doc with invalid data (non v1.0 compliant)
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => to_json({ test => 'test' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  # validator raises an exception with error message
  like($content->{error}, qr/Failed/, 'Correct error response');
  
  # now the index's empty, create the sample docs through the API
  my $docs = $indexer->docs;

  #
  # create first doc
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => &Registry::Utils::slurp_file($docs->[2]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackhub\/1/, 'Correct URI for created doc');
  $content = from_json($response->content);
  is($content->{data}[0]{id}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Correct content');
  #
  # attempt to submit trackdb with the same hub/assembly should fail
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => &Registry::Utils::slurp_file($docs->[2]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  # validator raises an exception with error message
  like($content->{error}, qr/same hub\/assembly/, 'Correct error response');
  #
  # create second doc
  $request = PUT('/api/trackhub/create',
  		 'Content-type' => 'application/json',
  		 'Content'      => &Registry::Utils::slurp_file($docs->[3]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackhub/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackhub\/2/, 'Correct URI for created doc');
  $content = from_json($response->content);
  is(scalar $content->{configuration}{bp}{members}{region}{members}{'bpDnaseRegionsBP_BP_DG-75_d01DNaseHOTSPOT_peakEMBL-EBI'}{shortLabel}, 'DG-75.DNase.DG-75', 'Correct content');
  #
  # POST request should fail: the endpoint is meant to translate
  # the assembly trackdb files of a remote public trackhub.
  # Must specify URL/type
  $request = POST('/api/trackhub/create',
  		  'Content-type' => 'application/json',
  		  'Content'      => &Registry::Utils::slurp_file($docs->[2]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create');
  ok(!$response->is_success, 'Doc create POST request unsuccessful');
  is($response->code, 400, 'POST request status code');
  #
  # should now have two documents which we can access via the /api/trackhub endpoint
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "Contains correct resource (document) URI") } 1 .. 2;
  #
  # the owner of these two documents should correspond to the creator
  $request = GET('/api/trackhub/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET Request to /api/trackhub/1');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{owner}, 'trackhub1', 'Correct trackhub owner');

  $request = GET('/api/trackhub/2');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET Request to /api/trackhub/2');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{owner}, 'trackhub1', 'Correct trackhub owner');

  #
  # /api/trackhub/create (POST): create new document as a direct
  # translation of an assembly trackdb file of a remote public
  # trackhub
  #
  # should fail if no data is provided
  $request = POST('/api/trackhub/create',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create (no data)');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide data/, 'Correct error response');
  #
  # should fail if no URL is given
  $request = POST('/api/trackhub/create',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ 'dummy' => 1 }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create (no URL)');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must specify.*?URL/i, 'Correct error response');
  #
  # should fail if URL is not correct
  my $URL = "http://";
  $request = POST('/api/trackhub/create?permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create (incorrect URL)');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/check the source/i, 'Correct error response');
  
  # test with some public hubs
  $URL = "http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants";
  #
  # should fail if wrong schema version is specified
  $request = POST('/api/trackhub/create?version=dummy',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create?version=dummy (wrong version)');
  is($response->code, 400, 'Request unsuccessful');  
  $content = from_json($response->content);
  like($content->{error}, qr/invalid version/i, 'Correct error response');
  #
  # should fail if unsupported schema version is specified
  $request = POST('/api/trackhub/create?version=v5.0',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create?version=v5.0 (unsupported version)');
  is($response->code, 400, 'Request unsuccessful');  
  $content = from_json($response->content);
  like($content->{error}, qr/not supported/i, 'Correct error response');
  #
  # request creation with schema version parameter: should get 3 docs
  $request = POST('/api/trackhub/create?version=v1.0&permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  ok($content, "Docs created");
  is(scalar keys %{$content}, 3, "Correct number of trackdb docs created");
  # check content of returned docs
  foreach my $id (keys %{$content}) {
    is($content->{$id}{type}, 'genomics', 'Default hub data type');
    is($content->{$id}{hub}{name}, 'cshl2013', 'Correct trackdb hub name');
    like($content->{$id}{hub}{longLabel}, qr/CSHL Biology of Genomes/, "Correct trackdb hub longLabel");
    # first data element is the same for all trackdbs
    is($content->{$id}{data}[0]{id}, 'repeatMasker_', "Correct trackdb data element");
    ok($content->{$id}{configuration}{repeatMasker_}, "Composite configuration exists");
    is($content->{$id}{configuration}{repeatMasker_}{shortLabel}, 'RepeatMasker', 'Composite short label');
  }
  #
  # attempt to submit track collections with the same hub/assembly as
  # that of another stored collection should fail
  $request = POST('/api/trackhub/create',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create');
  is($response->code, 400, 'Request unsuccessful');  
  $content = from_json($response->content);
  like($content->{error}, qr/same hub\/assembly/i, 'Correct error response');
  #
  # test with other public hubs
  $URL = 'http://smithlab.usc.edu/trackdata/methylation';
  $request = POST('/api/trackhub/create?permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL, type => 'epigenomics' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), "POST request to /api/trackhub/create?version=v1.0");
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  ok($content, "Docs created");
  is(scalar keys %{$content}, 8, "Eight trackdb docs created");
  my $id = (keys %{$content})[0];
  foreach my $id (keys %{$content}) {
    is($content->{$id}{type}, 'epigenomics', 'Correct hub type');
    is($content->{$id}{hub}{name}, 'Smith Lab Public Hub', 'Correct trackdb hub name');
    is($content->{$id}{hub}{shortLabel}, 'DNA Methylation', 'Correct trackdb hub shortLabel');
    is($content->{$id}{hub}{longLabel}, 'Hundreds of analyzed methylomes from bisulfite sequencing data', 'Correct trackdb hub longLabel');
    is($content->{$id}{version}, 'v1.0', 'Correct version');
    if ($content->{$id}{species}{tax_id} == 9615) {
      is($content->{$id}{assembly}{synonyms}, 'canFam3', 'Correct assembly synonym');
      is($content->{$id}{configuration}{Carmona_Dog_2014}{longLabel}, 'A Comprehensive DNA Methylation Profile of Epithelial-to-Mesenchymal Transition', 'Correct composite long label');
      is(scalar keys %{$content->{$id}{configuration}{Carmona_Dog_2014}{members}}, 7, 'Correct number of views');
      is($content->{$id}{configuration}{Carmona_Dog_2014}{members}{AMRCarmona_Dog_2014}{members}{CarmonaDog2014_DogMDCKAMR}{bigDataUrl}, 'http://smithlab.usc.edu/methbase/data/Carmona-Dog-2014/Dog_MDCK/tracks_canFam3/Dog_MDCK.amr.bb', 'Correct view member bigDataUrl');
    }
  }

  # Logout 
  $request = GET('/api/logout');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/logout');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{message}, qr/logged out/, 'Logged out');

  # any other following request should fail
  $request = GET('/api/trackhub/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub/:id');
  is($response->code, 401, 'Request unsuccessful 401');

}

done_testing();
