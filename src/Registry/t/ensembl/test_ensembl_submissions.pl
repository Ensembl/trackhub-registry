# Copyright [2015-2017] EMBL-European Bioinformatics Institute
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
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common;
use LWP::UserAgent;

use Catalyst::Test 'Registry';
use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

my $ua = LWP::UserAgent->new;
# my $server = 'http://193.62.54.43:5000';
# my $server = 'http://test.trackhubregistry.org';
my $server = 'http://localhost:3000';

# use Search::Elasticsearch;
# my $es = Search::Elasticsearch->new(cxn_pool => 'Sniff',
# 				    nodes => 'localhost:9200');

# my $query = 
#   {
#    filtered => {
#   		filter => {
#   			   # terms => { 
#   			   # 		 biosample_id => $biosample_ids
#   			   # 		}
#   			   term  => { biosample_id => 'samn03268375' }
#   			  }
#   	       }
#   };
#   { match_all => {} };
#   # {
#   #  match => { biosample_id => 'SAMN04601058 SAMN04601063 SAMN03268375' }
#   # };
# my $results = $es->search(index => 'test',
# 			  type  => 'trackdb',
# 			  body  => { query => $query });
# print Dumper $results;
# exit;

my $config = Registry->config()->{'Model::Search'};
my $indexer = Registry::Indexer->new(dir   => "$Bin/../trackhub-examples/",
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
$indexer->index_users();

# my ($user, $pass) = ('avullo', 'ALcsK32EX');
my ($user, $pass) = ('trackhub1', 'trackhub1'); 
my $request = GET("$server/api/login");
$request->headers->authorization_basic($user, $pass);
my $response = $ua->request($request);
my $auth_token;
if ($response->is_success) {
  $auth_token = from_json($response->content)->{auth_token};
  print "Logged in [$auth_token]\n" if $auth_token;
} else {
  die sprintf "Couldn't login: %s [%d]", $response->content, $response->code;
}

my $hubs = 
  [
   # Ensembl Plants hubs
   # {
   #  url => "ftp://ftp.ensemblgenomes.org/pub/misc_data/Track_Hubs/SRP051670/hub.txt",
   #  assemblies => { 'TGACv1' => 'GCA_900067645.1' }
   # },
   # },
   # {
   #  url => "ftp://ftp.ensemblgenomes.org/pub/misc_data/.TrackHubs/SRP033371/hub.txt",
   #  assemblies => { 'TAIR10' => 'GCA_000001735.1' }
   # },
   # {
   #  url => "ftp://ftp.ensemblgenomes.org/pub/misc_data/.TrackHubs/SRP010680/hub.txt",
   #  assemblies => { 'AGPv3' => 'GCA_000005005.5' },
   # },
   # {
   #  url => "ftp://ftp.ensemblgenomes.org/pub/misc_data/Track_Hubs/SRP051137/hub.txt",
   #  assemblies => { 'O.barthii_v1' => 'GCA_000182155.2' }
   # },
   #
   # VectorBase hubs
   # Hubs with some potential issues with species names
   # Glossina fuscipes fuscipes (Glossina_fuscipes in VB) 
   {
    url => "ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/glossina_fuscipes/VBRNAseq_group_SRP017755/hub.txt",
    assemblies => { 'GfusI1' => 'GCA_000671735.1' },
   },
   # Glossina palpalis gambiensis (Glossina_palpalis in VB) 
   {
    url => "ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/glossina_palpalis/VBRNAseq_group_SRP015954/hub.txt",
    assemblies => { 'GpapI1' => 'GCA_000818775.1' },
   },
   # Anopheles stephensi strain Indian (Anopheles_stephensiI in VB) 
   {
    url => "ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/anopheles_stephensi_indian/VBRNAseq_group_1369/hub.txt",
    assemblies => { 'AsteI2' => 'GCA_000300775.2' },
   },
   # control
   {
    url => "ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/anopheles_epiroticus/VBRNAseq_group_SRP043018/hub.txt",
    assemblies => { 'AepiE1' => 'GCA_000349105.1' },
   },
   #
   # test a few others of the newly added VB track hubs (as of 29/11/2016)
   {
    url => "ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/anopheles_coluzzii/VBRNAseq_group_1348/hub.txt",
    assemblies => { 'AcolM1' => 'GCA_000150765.1' },
   },
   {
    url => "ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/cimex_lectularius/VBRNAseq_group_1345/hub.txt",
    assemblies => { 'ClecH1' => 'GCA_000300775.2' },
   },
  ];

foreach my $hub (@{$hubs}) {
  $request = POST("$server/api/trackhub?permissive=1",
		  'Content-type' => 'application/json',
		  'Content'      => to_json($hub));
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  $response = $ua->request($request);
  if ($response->is_success) {
    printf "I have registered hub at %s\n", $hub->{url};
  } else {
    die sprintf "Couldn't register hub at %s: %s [%d]", $hub->{url}, $response->content, $response->code;
  } 
}

# Logout 
$request = GET("$server/api/logout");
$request->headers->header(user       => $user);
$request->headers->header(auth_token => $auth_token);
if ($response->is_success) {
  print "Logged out\n";
} else {
  print "Unable to logout\n";
} 

# $request = POST("$server/api/search/biosample",
# 		'Content-type' => 'application/json');
# ok($response = $ua->request($request), 'POST request to /api/search/biosample');
# is($response->code, 400, 'Request unsuccessful 400');
# my $content = from_json($response->content);
# like($content->{error}, qr/Missing list/, 'Correct error response');

# $request = POST("$server/api/search/biosample",
# 		'Content-type' => 'application/json',
# 		'Content'      => to_json({ ids => [] }));
# ok($response = $ua->request($request), 'POST request to /api/search/biosample');
# is($response->code, 400, 'Request unsuccessful 400');
# $content = from_json($response->content);
# like($content->{error}, qr/Empty list/, 'Correct error response');

# # first two belongs to first hub, third to second
# my $biosample_ids = [ 'SAMN04601058', 'SAMN04601063', 'SAMN04235789' ];
# $request = POST("$server/api/search/biosample",
# 		'Content-type' => 'application/json',
# 		'Content'      => to_json({ ids => $biosample_ids }));
# ok($response = $ua->request($request), 'POST request to /api/search/biosample');
# ok($response->is_success, 'Request successful');
# is($response->content_type, 'application/json', 'JSON content type');
# $content = from_json($response->content);
# print Dumper $content;

# $request = GET("$server/api/trackdb/AVCzG8pAaLx8j0yTm-ob");
# $request->headers->header(user       => $user);
# $request->headers->header(auth_token => $auth_token);
# $response = $ua->request($request);
# my $doc;
# if ($response->is_success) {
#   $doc = from_json($response->content);
# } else {  
#   print "Couldn't get trackDB\n";
# }

  # $request = POST('/api/trackhub?permissive=1',
  # 		  'Content-type' => 'application/json',
  # 		  'Content'      => to_json({ url => 'http://www.ebi.ac.uk/~tapanari/data/test/SRP036860/hub.txt', 
  # 					      assemblies => { "JGI2.0" => 'GCA_000002775.2' }
  # 					    }));
  # $request->headers->header(user       => 'trackhub1');
  # $request->headers->header(auth_token => $auth_token);
  # ok($response = request($request), 'POST request to /api/trackhub');
  # ok($response->is_success, 'Request successful 2xx');
  # is($response->content_type, 'application/json', 'JSON content type');
  # print Dumper $response;
  # $content = from_json($response->content);
  # is(scalar @{$content}, 3, "Correct number of trackdb docs created");
  # my @ids = map { $_ } @{$response->headers->{location}};

  # is(scalar @ids, 3, 'Corrent number of IDs');

  #
  # /api/trackdb (GET): get list 
  #

  #
  # /api/trackhub (GET): get list of trackhubs
  #
  # $request = GET('/api/trackhub');
  # $request->headers->header(user       => 'trackhub1');
  # $request->headers->header(auth_token => $auth_token);
  # ok($response = request($request), 'GET request to /api/trackdb');
  # ok($response->is_success, 'Request successful 2xx');
  # is($response->content_type, 'application/json', 'JSON content type');
  # $content = from_json($response->content);
  # use Data::Dumper; print Dumper $content;

  #
  # /api/trackdb (GET): get trackdb with the given ID
  #
  # $request = GET($ids[0]);
  # $request->headers->header(user       => 'trackhub1');
  # $request->headers->header(auth_token => $auth_token);
  # ok($response = request($request), sprintf "GET request to %s", $ids[0]);
  # ok($response->is_success, 'Request successful 2xx');
  # is($response->content_type, 'application/json', 'JSON content type');
  # $content = from_json($response->content);
  # open my $FH, ">tmp.json" or die "Cannot open file: $!\n";
  # use Data::Dumper; print $FH Dumper $content;
  
done_testing();
