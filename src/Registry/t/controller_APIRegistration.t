# Copyright [2015-2019] EMBL-European Bioinformatics Institute
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
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;
use Registry::User::TestDB;
use Test::WWW::Mechanize::Catalyst;
use Registry::Utils; # es_running, slurp_file
use Test::HTTP::MockServer;

BEGIN {
  use FindBin qw/$Bin/;
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}


my $INDEX_NAME = 'trackhubs'; # Matches registry_testing.conf
my $INDEX_TYPE = 'trackdb';


my $db = Registry::User::TestDB->new(
  config => {
    driver => 'SQLite',
    file => './thr_users.db', # This has to match registry_testing.conf db name
    create => 1
  },
);
# Make a test user for the application
my $digest = Digest->new('SHA-256');
my $salt = 'afs]dt42!'; # This has to match registry_testing.conf pre_salt

$digest->add($salt);
$digest->add('password');

my $user = $db->schema->resultset('User')->create({
  username => 'test-dude',
  password => $digest->b64digest,
  email => 'test@home',
  continuous_alert => 1
});
$user->add_to_roles({ name => 'user' });


use Catalyst::Test 'Registry';
use_ok 'Registry::Controller::API::Registration';


my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');
$mech->get_ok('http://127.0.0.1/', 'Trackhub Registry running');

my $request = HTTP::Request::Common::GET('http://127.0.0.1/api/login');
$request->authorization_basic('test-dude', 'password');
$mech->request($request);

cmp_ok ($mech->status, '==', 200, 'Authentication achieved');
ok(my $response = $mech->response, 'Request to log in');
ok($response->is_success, 'Login happened');
my $content = from_json($response->content);
ok(exists $content->{auth_token}, 'Log in includes an auth_token we can use in the API');
my $auth_token = $content->{auth_token};

# Host a fake hub on localhost that we can reference in submitted hubs

my $fake_server = Test::HTTP::MockServer->new();
my $fake_response = sub {
  my ($request, $response) = @_;
  $response->code(200);
  if ($request->uri =~ m/hub.txt/ ) {
    $response->content(Registry::Utils::slurp_file("$Bin/track_hub/test_hub_1/hub.txt"));
  } elsif ($request->uri =~ m/genomes.txt/) {
    $response->content(Registry::Utils::slurp_file("$Bin/track_hub/test_hub_1/genomes.txt"));
  } elsif ($request->uri =~ m/trackdb/) {
    $response->content(Registry::Utils::slurp_file("$Bin/track_hub/test_hub_1/grch38/trackDb.txt"));
  }
};
$fake_server->start_mock_server($fake_response);

$mech->get_ok('127.0.0.1:9200/hub.txt', 'Test hub server online');
my $hub_port = $fake_server->port(); # port is randomised on start, so we have to keep any eye on it

# Submit a new hub

$mech->add_header( user => 'test-dude', 'auth-token' => $auth_token);
$mech->post_ok(
  "http://localhost/api/trackhub/?permissive=1",
  { 
    content => to_json({
      url => "http://localhost:$hub_port/hub.txt",
      assemblies => 'GRCh38',
      public => 1 # technically not required, but explicit here
    })
  },
  'Submit new trackhub using authentication token'
);

# One hub is already registered during test setup, we try to submit it again

# Now register another hub but do not make it available for search
note sprintf "Submitting hub ultracons (not searchable)";
$request = POST('/api/trackhub?permissive=1',
    'Content-type' => 'application/json',
    'Content'      => to_json({ url => 'http://genome-test.gi.ucsc.edu/~hiram/hubs/GillBejerano/hub.txt', public => 0 }));
$request->headers->header(user       => 'trackhub1');
$request->headers->header(auth_token => $auth_token);
ok($response = request($request), 'POST request to /api/trackhub');
ok($response->is_success, 'Request successful 2xx');
is($response->content_type, 'application/json', 'JSON content type');

# Logout
$request = GET('/api/logout');
$request->headers->header(user       => 'trackhub1');
$request->headers->header(auth_token => $auth_token);
ok($response = request($request), 'GET request to /api/logout');
ok($response->is_success, 'Request successful 2xx');

done_testing();

=POD


  my $auth_token = log_in('trackhub1','trackhub1');
  
  #
  # /api/trackdb (GET): get list of documents with their URIs
  #
  my $content = get_user_trackdbs('trackhub1',$auth_token,200);
  is(keys %{$content}, 2, "Number of trackhub1 docs");
  map { like($content->{$_}, qr/api\/trackdb\/$_/, "trackhub1 owns submitted (document) URI api/trackdb/$_") } 1 .. 2;
  #
  # a different user should get a different set of documents
  my $auth_token2 = log_in('trackhub2','trackhub2');
  $content = get_user_trackdbs('trackhub2',$auth_token2,200);
  is(keys %{$content}, 1, "Number of trackhub2 docs");
  like($content->{3}, qr/api\/trackdb\/3/, "trackhub2 owns submitted URI api/trackdb/3");
  #
  # and another user again
  my $auth_token3 = log_in('trackhub3','trackhub3');
  $content = get_user_trackdbs('trackhub3',$auth_token3,200);
  is(keys %{$content}, 1, "Number of trackhub3 docs");
  like($content->{4}, qr/api\/trackdb\/4/, "trackhub3 owns submitted URI api/trackdb/4");

  #
  # /api/trackdb/:id (GET)
  #
  # request document 1 for trackhub1
  $content = get_user_trackdbs('trackhub1',$auth_token,200,'1');
  is(scalar @{$content->{data}}, 1, 'One trackdb');
  is($content->{data}[0]{id}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Trackdb name');
  is($content->{configuration}{bpDnaseRegionsC0010K46DNaseEBI}{bigDataUrl}, 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Trackdb url');
  #
  # request incorrect document (belongs to another provider)
  $content = get_user_trackdbs('trackhub1',$auth_token,400,'3');
  like($content->{error}, qr/Cannot fetch/, 'trackhub1 cannot fetch hub 3 belonging to trackhub2');
  #
  # request incorrect document (does not exist)
  $content = get_user_trackdbs('trackhub1',$auth_token,404,'5');
  like($content->{error}, qr/Could not find/, 'trackhub1 cannot request non-existent hubs');

  #
  # /api/trackdb/:id (PUT) update document
  #
  # Try to update a document that isn't yours. Invalid request
  $content = update_trackdb('trackhub1',$auth_token,400,'3');
  like($content->{error}, qr/does not belong/, 'Cannot update trackdb 3 as it is not yours');
  #
  # request incorrect document (does not exist)
  $content = update_trackdb('trackhub1',$auth_token,404,'5');
  like($content->{error}, qr/does not exist/, 'Cannot update trackdb5 as it is not there');
  
  # request to update a doc but do not supply data
  $content = update_trackdb('trackhub1',$auth_token,400,'1');
  like($content->{error}, qr/You must provide a doc/, 'Cannot update a trackdb without providing a replacement');
  
  # request to update doc with invalid content (non v1.0 compliant)
  $content = update_trackdb('trackhub1',$auth_token,400,'1',to_json({ test => 'test' }));
  # the validator raises an exception with the error message, check
  like($content->{error}, qr/Failed/, 'Validator failed');
  # update doc1

  $content = update_trackdb(
    'trackhub1',
    $auth_token,
    200,
    '1',
    to_json({
      type    => 'epigenomics',
      hub     => { name => 'Test', shortLabel => 'Test Hub', longLabel => 'Test Hub' },
      version => 'v1.0',
      species => { tax_id => 9606, scientific_name => 'Homo sapiens' },
      assembly => { accession => 'GCA_000001405.15', name => 'GRCh38' },
      data => [ { id => 'test', molecule => 'genomic_DNA' } ],
      configuration => { test => { shortLabel => 'test' } }
    })
  );
  
  is($content->{data}[0]{id}, 'test', 'Correct updated content');
  is($content->{owner}, 'trackhub1', 'Correct owner');

  #
  # /api/trackdb/:id (DELETE) delete document
  #
  # request incorrect document (belongs to another provider)
  $content = delete_url('trackhub1',$auth_token,400,'/api/trackdb','3');
  like($content->{error}, qr/does not belong/, 'Correct error response');
  #
  # request incorrect document (does not exist)
  $content = delete_url('trackhub1',$auth_token,404,'/api/trackdb','5');
  like($content->{error}, qr/Could not find/, 'Correct error response');

  # delete doc1
  $content = delete_url('trackhub1',$auth_token,200,'/api/trackdb','1');
  is($content->{species}{tax_id}, 9606, 'Content of deleted resource');

  # request for deleted doc should fail
  $content = get_user_trackdbs('trackhub1',$auth_token,404,'1');
  like($content->{error}, qr/Could not find/, 'Error correct for fetching a deleted record');

  note "Re-creating index test";
  $indexer->create_indices(); # do not index the documents this time through the indexer, the API will do that
  $indexer->index_users();

  #
  # Re-Authenticate since the auth_token is deleted
  #
  $auth_token = log_in('trackhub1', 'trackhub1');
  
  #
  # /api/trackdb/create (POST): create new document
  #
  # request to create a doc but do not supply data
  $content = create_trackdb('trackhub1',$auth_token,400,undef);
  like($content->{error}, qr/You must provide a doc/, 'POST with no Content causes an error');

  #
  # request to create a doc with invalid data (non v1.0 compliant)
  $content = create_trackdb('trackhub1',$auth_token,400, to_json({ test => 'test'}) );
  # validator raises an exception with error message
  like($content->{error}, qr/Failed/, 'Validator rejects bad hub content');
  
  # The index is empty, create sample docs through the API
  my $docs = $indexer->docs;
  #
  # create first doc
  $content = create_trackdb('trackhub1',$auth_token,201,&Registry::Utils::slurp_file($docs->[2]{file}));
  is($content->{data}[0]{id}, 'bpDnaseRegionsC0010K46DNaseEBI', 'Correct content');
  #
  # attempt to submit trackdb with the same hub/assembly should fail
  $content = create_trackdb('trackhub1',$auth_token,400,&Registry::Utils::slurp_file($docs->[2]{file}));
  # validator raises an exception with error message
  like($content->{error}, qr/same hub\/assembly/, 'Correct error from submitting the same hub and assembly');

  #
  # create second doc
  $content = create_trackdb('trackhub1',$auth_token,201,&Registry::Utils::slurp_file($docs->[3]{file}));
  is(scalar $content->{configuration}{bp}{members}{region}{members}{'bpDnaseRegionsBP_BP_DG-75_d01DNaseHOTSPOT_peakEMBL-EBI'}{shortLabel}, 'DG-75.DNase.DG-75', 'Correct content');
  #
  # should now have two documents which we can access via the /api/trackdb endpoint
  $content = get_user_trackdbs('trackhub1',$auth_token,200);
  my @ids = keys %{$content};
  map { like($content->{$_}, qr/api\/trackdb\/$_$/, "Contains correct resource (document) URI") } @ids;
  #
  # the owner of these two documents should correspond to the creator
  foreach my $id (@ids) {
    $content = get_user_trackdbs('trackhub1',$auth_token,200,$id);
    is($content->{owner}, 'trackhub1', 'Correct trackdb owner');
  }

  #
  # /api/trackhub (POST): create new documents as direct
  # translations of assembly trackdb files of a remote public trackhub
  #
  # Cause failure when no data is provided
  
  $content = create_hub('trackhub1',$auth_token,400,undef);
  like($content->{error}, qr/You must provide data/, 'Correct error response');
  #
  # Cause failure with no URL in request
  $content = create_hub('trackhub1',$auth_token,400,to_json({ 'dummy' => 1 }));
  like($content->{error}, qr/You must specify.*?URL/i, 'Correct error response');

  #
  # should fail if hub URL is not correct
  $content = create_hub('trackhub1',$auth_token,400,to_json({ url => 'http://' }));
  # like($content->{error}, qr/check the source/i, 'Correct error response');

  # test with some public hubs
  my $URL = "http://genome-test.gi.ucsc.edu/~hiram/hubs/Plants";
  
  # Fail if wrong schema version is specified
  $content = create_hub('trackhub1',$auth_token,400,to_json({ url => $URL }),['version=dummy']);
  like($content->{error}, qr/invalid version/i, 'Unsupported nonsense trackhub version creates error response');
  #
  # should fail if unsupported schema version is specified

  $content = create_hub('trackhub1',$auth_token,400,to_json({ url => $URL }),['version=v5.0']);
  like($content->{error}, qr/not supported/i, 'Unsupported trackhub version creates error response');

  # request creation with schema version parameter: should get 3 docs
  $content = create_hub('trackhub1',$auth_token,201,to_json({ url => $URL }),['version=v1.0','permissive=1']);
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
  $content = create_hub('trackhub1',$auth_token,201,to_json({ url => $URL }),['version=v1.0','permissive=1']);
  ok($content, "Docs updated");
  
  # [ENSCORESW-1713]. Resubmission can fail, in this case we want to
  # re-establish the previous hub content, since it's first deleted.
  $content = create_hub(
    'trackhub1',
    $auth_token,
    400,
    to_json({ url => $URL, assemblies => { araTha1 => 'dummy'} }),
    ['version=v1.0','permissive=1']
  );
  like($content->{error}, qr/does not comply/i, 'Failure due to incorrect assembly');

  my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');
  $mech->get_ok('/', 'Requested main page');
  $mech->submit_form_ok({
      form_number => 1,
      fields      => {
          q => 'hub.shortLabel:plants'
      },
    }, 'Submit search query for plants hub'
  );
  $mech->content_like(qr/Track Collections 1 to 3 of 3/, 'Got original Plants trackDBs with appropriate pagination');

  #
  # Submission of the same hub by another user should fail
  #

  $auth_token2 = log_in('trackhub2', 'trackhub2');
  $content = create_hub('trackhub2',$auth_token2,400,to_json({ url => $URL }));
  like($content->{error}, qr/by another user/i, 'Another user owns this hub, submission rejected');

  #
  # Test submission of same hub with assembly name -> INSDC accession map
  # This updates the original record
  #
  $content = create_hub(
    'trackhub1',
    $auth_token,
    201,
    to_json({ 
      url => 'http://genome-test.gi.ucsc.edu/~hiram/hubs/Plants/hub.txt', 
      assemblies => {
                   araTha1 => 'GCA_000001735.1',
                   ricCom1 => 'GCA_000151685.2',
                   braRap1 => 'GCA_000309985.1'
                  }
    }),
    ['permissive=1']
  );
  ok($content, "Docs created");
  is(scalar @{$content}, 3, "Correct number of trackdb docs created");

  #
  # Test /api/trackhub (GET) with no ID
  #
  $content = get_hub('trackhub1',$auth_token,200);
  # here we also test the update of the Plant TrackHub
  # did not alter the number of hubs by deleting the previously
  # existing trackDbs

  is(scalar @{$content}, 2, 'Number of hubs'); #Comment: As Smithlab hub was commented out, we expect only 2
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
      is(scalar @{$hub->{trackdbs}}, 11, 'Number of trackDbs');
    }
  }

  #
  # Test /api/trackhub/:id (GET)
  #
  my $hub = get_hub('trackhub1',$auth_token,200,'cshl2013');
  is($hub->{name}, 'cshl2013', 'Hub name');
  is($hub->{shortLabel}, 'Plants', 'Hub short label');
  is(scalar @{$hub->{trackdbs}}, 3, 'Number of trackDbs');
  foreach my $trackdb (@{$hub->{trackdbs}}) {
    ok(
      ($trackdb->{species}->{tax_id} == 3702) || 
      ($trackdb->{species}->{tax_id} == 3711) || 
      ($trackdb->{species}->{tax_id} == 3988), 
    'trackDb species');
    ok(
      ($trackdb->{assembly}->{accession} eq 'GCA_000151685.2') || 
      ($trackdb->{assembly}->{accession} eq 'GCA_000309985.1') || 
      ($trackdb->{assembly}->{accession} eq 'GCA_000001735.1'),
     'trackDb assembly');
    like($trackdb->{uri}, qr/api\/trackdb/, 'trackDb uri');
  }

  #
  # Test /api/trackhub/:id (DELETE)
  #
  # request incorrect hub (does not exist)
  $content = delete_url('trackhub1',$auth_token,404,'api/trackhub','xxxxxx');
  like($content->{error}, qr/Could not find/, 'Correct error response');
  #
  # request to delete existing hub
  $content = delete_url('trackhub1',$auth_token,200,'api/trackhub','Blueprint_Hub');
  like($content->{message}, qr/deleted/i, 'Track hub delete message');
  #
  # if we request the hub we shouldn't get content
  $content = get_hub('trackhub1',$auth_token,404,'Blueprint_Hub');
  like($content->{error}, qr/Could not find/, 'Blueprint_Hub is gone');
  
  log_out('trackhub1',$auth_token);
  
  # any other following request should fail
  $content = get_user_trackdbs('trackhub1',$auth_token,401,'1');


done_testing();


sub log_in {
  my ($user,$pass) = @_;
  my $request = GET('/api/login');
  $request->headers->authorization_basic($user, $pass);
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};
  return $auth_token;
}

sub log_out {
  my ($user,$auth_token) = @_;
  my $request = GET('/api/logout');
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), 'GET request to /api/logout');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  like($content->{message}, qr/logged out/, 'Logged out');
}

sub get_user_trackdbs {
  my ($user,$auth_token,$expected_code,$id) = @_;
  note "Getting tracks for user $user";
  my $url = '/api/trackdb';
  $url .= '/'.$id if defined $id;
  my $request = GET($url);
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), "GET request to $url");
  cmp_ok($response->code,'==',$expected_code, "Response $expected_code as expected");
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  return $content;
}

sub get_hub {
  my ($user,$auth_token,$expected_code,$id) = @_;
  note "Getting hub $id for user $user";
  my $url = '/api/trackhub';
  $url .= '/'.$id if defined $id;
  my $request = GET($url);
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), 'GET request to '.$url);
  cmp_ok($response->code,'==',$expected_code, "Response $expected_code as expected");
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  return $content;
}

sub create_trackdb {
  my ($user,$auth_token,$expected_code, $content) = @_;
  my $request = POST(
    '/api/trackdb/create',
    'Content-type' => 'application/json',
    'Content' => $content
  );
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), 'POST request to /api/trackdb/create');
  is($response->code, $expected_code, "Response $expected_code as expected");
  if ($expected_code == 201) {
    like($response->header('location'), qr/\/api\/trackdb\/[A-Za-z0-9_-]+?$/, 'Valid URI for created doc');
  }
  $content = from_json($response->content);
  return $content;
}

sub create_hub {
  my ($user,$auth_token,$expected_code,$content,$params) = @_;

  my $url = '/api/trackhub';
  if ($params) { 
    $url .= '?'.join('&',@$params);
  }
  my $request = POST(
    $url,
    'Content-type' => 'application/json',
    'Content'      => $content
  );
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), "POST request to $url");
  is($response->code, $expected_code, "Response $expected_code as expected");
  $content = from_json($response->content);
  return $content;
}

sub update_trackdb { 
  my ($user,$auth_token,$expected_code,$id,$content) = @_;
  my $request = PUT('/api/trackdb/'.$id, 'Content-type' => 'application/json', 'Content' => $content);
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), 'PUT request to /api/trackdb/'.$id);
  is($response->code, $expected_code, "Response $expected_code as expected");
  $content = from_json($response->content);
  return $content;
}

sub delete_url {
  my ($user, $auth_token, $expected_code, $url, $id) = @_;
  my $request = DELETE($url.'/'.$id);
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response;
  ok($response = request($request), 'DELETE request to '.$url.'/'.$id);
  is($response->code, $expected_code, "Response $expected_code as expected");
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  return $content;
}
