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
    241 unless &Registry::Utils::es_running();

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
  # Authenticate
  #
  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
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
  ok($response = request($request), 'GET request to /api/trackdb');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 2, "Number of trackhub1 docs");
  map { like($content->{$_}, qr/api\/trackdb\/$_/, "Contains correct resource (document) URI") } 1 .. 2;
  #
  # a different user should get a different set of documents
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub2', 'trackhub2');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token2 = $content->{auth_token};
  $request = GET('/api/trackdb');
  $request->headers->header(user       => 'trackhub2');
  $request->headers->header(auth_token => $auth_token2);
  ok($response = request($request), 'GET request to /api/trackdb');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 1, "Number of trackhub2 docs");
  like($content->{3}, qr/api\/trackdb\/3/, "Contains correct resource (document) URI");
  #
  # and another user again
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub3', 'trackhub3');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token3 = $content->{auth_token};
  $request = GET('/api/trackdb');
  $request->headers->header(user       => 'trackhub3');
  $request->headers->header(auth_token => $auth_token3);
  ok($response = request($request), 'GET request to /api/trackdb');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(keys %{$content}, 1, "Number of trackhub3 docs");
  like($content->{4}, qr/api\/trackdb\/4/, "Contains correct resource (document) URI");

  #
  # /api/trackdb/:id (GET)
  #
  # go back to user trackhub1 authentication
  # $request = GET('/api/login');
  # $request->headers->authorization_basic('trackhub1', 'trackhub1');
  # ok($response = request($request), 'Request to log in');
  # $content = from_json($response->content);
  # ok(exists $content->{auth_token}, 'Logged in');
  # $auth_token = $content->{auth_token};
  #
  # request correct document
  $request = GET('/api/trackdb/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET Request to /api/trackdb/1');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{data}}, 1, 'One trackdb');
  is($content->{data}[0]{id}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Trackdb name');
  is($content->{configuration}{bpDnaseRegionsC0010K46DNaseEBI}{bigDataUrl}, 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Trackdb url');
  #
  # request incorrect document (belongs to another provider)
  $request = GET('/api/trackdb/3');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackdb/3');
  is($response->code, 400, 'Request unsuccessful 400');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Cannot fetch/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $request = GET('/api/trackdb/5');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackdb/3');
  is($response->code, 404, 'Request unsuccessful 404');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  #
  # /api/trackdb/:id (PUT) update document
  #
  # request incorrect document (belongs to another provider)
  $request = PUT('/api/trackdb/3',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackdb/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not belong/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $request = PUT('/api/trackdb/5',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackdb/3');
  is($response->code, 404, 'Request unsuccessful 404');
  $content = from_json($response->content);
  like($content->{error}, qr/does not exist/, 'Correct error response');
  
  # request to update a doc but do not supply data
  $request = PUT('/api/trackdb/1',
  		 'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackdb/1');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');
  
  # request to update doc with invalid content (non v1.0 compliant)
  $request = PUT('/api/trackdb/1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ test => 'test' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackdb/1');
  is($response->code, 400, 'Request unsuccessful 400');
  # the validator raises an exception with the error message, check
  $content = from_json($response->content);
  like($content->{error}, qr/Failed/, 'Correct error response');

  # update doc1
  $request = PUT('/api/trackdb/1',
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
  ok($response = request($request), 'POST request to /api/trackdb/1');
  ok($response->is_success, 'Doc update request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{data}[0]{id}, 'test', 'Correct updated content');
  is($content->{owner}, 'trackhub1', 'Correct owner');

  #
  # /api/trackdb/:id (DELETE) delete document
  #
  # request incorrect document (belongs to another provider)
  $request = DELETE('/api/trackdb/3');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackdb/3');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/does not belong/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $request = DELETE('/api/trackdb/5');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackdb/5');
  is($response->code, 404, 'Request unsuccessful 404');
  $content = from_json($response->content);
  like($content->{error}, qr/Could not find/, 'Correct error response');

  # delete doc1
  $request = DELETE('/api/trackdb/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'DELETE request to /api/trackdb/1');
  ok($response->is_success, 'Request successful 2xx');
  $content = from_json($response->content);
  is($content->{species}{tax_id}, 9606, 'Content of deleted resource');

  # request for deleted doc should fail
  $request = GET('/api/trackdb/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackdb/1');
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
  # /api/trackdb/create (POST): create new document
  #
  # request to create a doc but do not supply data
  $request = POST('/api/trackdb/create',
		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackdb/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide a doc/, 'Correct error response');
  #
  # request to create a doc with invalid data (non v1.0 compliant)
  $request = POST('/api/trackdb/create',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ test => 'test' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackdb/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  # validator raises an exception with error message
  like($content->{error}, qr/Failed/, 'Correct error response');
  
  # now the index's empty, create the sample docs through the API
  my $docs = $indexer->docs;

  #
  # create first doc
  $request = POST('/api/trackdb/create',
		  'Content-type' => 'application/json',
		  'Content'      => &Registry::Utils::slurp_file($docs->[2]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackdb/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackdb\/[A-Za-z0-9_-]+?$/, 'Correct URI for created doc');
  $content = from_json($response->content);
  is($content->{data}[0]{id}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Correct content');
  #
  # attempt to submit trackdb with the same hub/assembly should fail
  $request = POST('/api/trackdb/create',
		  'Content-type' => 'application/json',
		  'Content'      => &Registry::Utils::slurp_file($docs->[2]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackdb/create');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  # validator raises an exception with error message
  like($content->{error}, qr/same hub\/assembly/, 'Correct error response');
  #
  # create second doc
  $request = POST('/api/trackdb/create',
		  'Content-type' => 'application/json',
		  'Content'      => &Registry::Utils::slurp_file($docs->[3]{file}));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'PUT request to /api/trackdb/create');
  ok($response->is_success, 'Doc create request successful');
  is($response->code, 201, 'Request successful 201');
  is($response->content_type, 'application/json', 'JSON content type');
  like($response->header('location'), qr/\/api\/trackdb\/[A-Za-z0-9_-]+?$/, 'Correct URI for created doc');
  $content = from_json($response->content);
  is(scalar $content->{configuration}{bp}{members}{region}{members}{'bpDnaseRegionsBP_BP_DG-75_d01DNaseHOTSPOT_peakEMBL-EBI'}{shortLabel}, 'DG-75.DNase.DG-75', 'Correct content');
  #
  # should now have two documents which we can access via the /api/trackdb endpoint
  $request = GET('/api/trackdb');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackdb');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  my @ids = keys %{$content};
  map { like($content->{$_}, qr/api\/trackdb\/$_$/, "Contains correct resource (document) URI") } @ids;
  #
  # the owner of these two documents should correspond to the creator
  foreach my $id (@ids) {
    $request = GET("/api/trackdb/$id");
    $request->headers->header(user       => 'trackhub1');
    $request->headers->header(auth_token => $auth_token);
    ok($response = request($request), "GET Request to /api/trackdb/$id");
    ok($response->is_success, 'Request successful 2xx');
    is($response->content_type, 'application/json', 'JSON content type');
    $content = from_json($response->content);
    is($content->{owner}, 'trackhub1', 'Correct trackdb owner');
  }

  #
  # /api/trackhub (POST): create new documents as direct
  # translations of assembly trackdb files of a remote public trackhub
  #
  # should fail if no data is provided
  $request = POST('/api/trackhub',
  		  'Content-type' => 'application/json');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackdb (no data)');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must provide data/, 'Correct error response');
  #
  # should fail if no URL is given
  $request = POST('/api/trackhub',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ 'dummy' => 1 }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub (no URL)');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/You must specify.*?URL/i, 'Correct error response');
  #
  # should fail if URL is not correct
  my $URL = "http://";
  $request = POST('/api/trackhub?permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub (incorrect URL)');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);
  like($content->{error}, qr/check the source/i, 'Correct error response');
  
  # test with some public hubs
  $URL = "http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants";
  #
  # should fail if wrong schema version is specified
  $request = POST('/api/trackhub?version=dummy',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub?version=dummy (wrong version)');
  is($response->code, 400, 'Request unsuccessful');  
  $content = from_json($response->content);
  like($content->{error}, qr/invalid version/i, 'Correct error response');
  #
  # should fail if unsupported schema version is specified
  $request = POST('/api/trackhub?version=v5.0',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub?version=v5.0 (unsupported version)');
  is($response->code, 400, 'Request unsuccessful');
  $content = from_json($response->content);
  like($content->{error}, qr/not supported/i, 'Correct error response');
  #
  # request creation with schema version parameter: should get 3 docs
  $request = POST('/api/trackhub?version=v1.0&permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub (Plants Hub)');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  # use Data::Dumper; print Dumper $response->header('Location');
  $content = from_json($response->content);
  ok($content, "Docs created");
  is(scalar @{$content}, 3, "Correct number of trackdb docs created");
  # check content of returned docs
  foreach my $trackdb (@{$content}) {
    is($trackdb->{type}, 'genomics', 'Default hub data type');
    is($trackdb->{hub}{name}, 'cshl2013', 'Correct trackdb hub name');
    like($trackdb->{hub}{longLabel}, qr/CSHL Biology of Genomes/, "Correct trackdb hub longLabel");
    # first data element is the same for all trackdbs
    is($trackdb->{data}[0]{id}, 'repeatMasker_', "Correct trackdb data element");
    ok($trackdb->{configuration}{repeatMasker_}, "Composite configuration exists");
    is($trackdb->{configuration}{repeatMasker_}{shortLabel}, 'RepeatMasker', 'Composite short label');
  }
  #
  # Resubmission is interpreted as an update request
  # Previously inserted docs should be deleted, and replaced
  # by new ones
  #
  $request = POST('/api/trackhub?version=v1.0&permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub (Plants Hub)');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  ok($content, "Docs created");
  #
  # Submission of the same hub by another user should fail
  #
  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub2', 'trackhub2');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token2 = $content->{auth_token};
  $request = POST('/api/trackhub?version=v1.0&permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub2');
  $request->headers->header(auth_token => $auth_token2);
  ok($response = request($request), 'POST request to /api/trackhub (Plants Hub)');
  is($response->code, 400, 'Request unsuccessful');
  $content = from_json($response->content);
  like($content->{error}, qr/by another user/i, 'Correct error response');
  #
  # Test submission of same hub with assembly name -> INSDC accession map
  #
  $request = POST('/api/trackhub?permissive=1',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ url => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt',
					      assemblies => {
							     araTha1 => 'GCA_000001735.1',
							     ricCom1 => 'GCA_000151685.2',
							     braRap1 => 'GCA_000309985.1'
							    }
					    }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub (Plants Hub)');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  ok($content, "Docs created");
  is(scalar @{$content}, 3, "Correct number of trackdb docs created");

  #
  # test with other public hubs
  $URL = 'http://smithlab.usc.edu/trackdata/methylation';
  $request = POST('/api/trackhub?permissive=1',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL, type => 'epigenomics' }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), "POST request to /api/trackhub?version=v1.0 (Methylation Hub)");
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  ok($content, "Docs created");
  is(scalar @{$content}, 10, "Ten trackdb docs created");
  foreach my $trackdb (@{$content}) {
    is($trackdb->{type}, 'epigenomics', 'Correct hub type');
    is($trackdb->{hub}{name}, 'Smith Lab Public Hub', 'Correct trackdb hub name');
    is($trackdb->{hub}{shortLabel}, 'DNA Methylation', 'Correct trackdb hub shortLabel');
    is($trackdb->{hub}{longLabel}, 'Hundreds of analyzed methylomes from bisulfite sequencing data', 'Correct trackdb hub longLabel');
    is($trackdb->{version}, 'v1.0', 'Correct version');
    if ($trackdb->{species}{tax_id} == 9615) {
      is($trackdb->{assembly}{synonyms}, 'canFam3', 'Correct assembly synonym');
      is($trackdb->{configuration}{Carmona_Dog_2014}{longLabel}, 'A Comprehensive DNA Methylation Profile of Epithelial-to-Mesenchymal Transition', 'Correct composite long label');
      is(scalar keys %{$trackdb->{configuration}{Carmona_Dog_2014}{members}}, 7, 'Correct number of views');
      is($trackdb->{configuration}{Carmona_Dog_2014}{members}{AMRCarmona_Dog_2014}{members}{CarmonaDog2014_DogMDCKAMR}{bigDataUrl}, 'http://smithlab.usc.edu/methbase/data/Carmona-Dog-2014/Dog_MDCK/tracks_canFam3/Dog_MDCK.amr.bb', 'Correct view member bigDataUrl');
    }
  }

  #
  # Test /api/trackhub
  #
  $request = GET('/api/trackhub');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  # here we also test the update of the Plant TrackHub
  # did not alter the number of hubs by deleting the previously
  # existing trackDbs
  is(scalar @{$content}, 3, 'Number of hubs');
  foreach my $hub (@{$content}) {
    if ($hub->{name} eq 'Blueprint_Hub') {
      is($hub->{longLabel}, 'Blueprint Epigenomics Data Hub', 'Hub long label');
      is(scalar @{$hub->{trackdbs}}, 2, 'Number of trackDbs');
      is($hub->{trackdbs}[0]{species}, 9606, 'trackDb species');
      like($hub->{trackdbs}[0]{assembly}, qr/GCA_000001405/, 'trackDb assembly');
      like($hub->{trackdbs}[0]{uri}, qr/api\/trackdb/, 'trackDb uri');
      is($hub->{trackdbs}[1]{species}, 9606, 'trackDb species');
      like($hub->{trackdbs}[1]{assembly}, qr/GCA_000001405/, 'trackDb assembly');
      like($hub->{trackdbs}[1]{uri}, qr/api\/trackdb/, 'trackDb uri');
    } elsif ($hub->{name} eq 'cshl2013') {
      is($hub->{shortLabel}, 'Plants', 'Hub short label');
      is(scalar @{$hub->{trackdbs}}, 3, 'Number of trackDbs');
      foreach my $trackdb (@{$hub->{trackdbs}}) {
	ok(($trackdb->{species} == 3702) || ($trackdb->{species} == 3711) || ($trackdb->{species} == 3988), 'trackDb species');
	ok(($trackdb->{assembly} eq 'GCA_000151685.2') || ($trackdb->{assembly} eq 'GCA_000309985.1') || ($trackdb->{assembly} eq 'GCA_000001735.1'), 'trackDb assembly');
	like($trackdb->{uri}, qr/api\/trackdb/, 'trackDb uri');
      }
    } elsif ($hub->{name} eq 'Smith Lab Public Hub') {
      is($hub->{shortLabel}, 'DNA Methylation', 'Hub short label');
      is(scalar @{$hub->{trackdbs}}, 10, 'Number of trackDbs');
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
  $request = GET('/api/trackdb/1');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/trackdb/:id');
  is($response->code, 401, 'Request unsuccessful 401');

}

done_testing();
