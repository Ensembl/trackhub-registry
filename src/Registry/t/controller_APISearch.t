# Copyright [2015-2016] EMBL-European Bioinformatics Institute
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
use Data::Dumper;
use LWP::Simple;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use Catalyst::Test 'Registry';
use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

SKIP: {
  skip "Cannot run tests: either elasticsearch is not running or there's no internet connection",
    95 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();

  note 'Preparing data for test (indexing users)';
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
  $indexer->index_users();

  # submit some public hubs
  my @public_hubs = (
		     # { name => 'polyA', url => 'http://johnlab.org/xpad/Hub/UCSC.txt' },
		     { name => 'mRNA', url => 'http://www.mircode.org/ucscHub/hub.txt' },
		     { name => 'blueprint', url => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub' },
		     { name => 'plants', url => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt' },
		     { name => 'ensembl', url => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt' },
		     { name => 'rnaseq', url => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt' },
		     { name => 'zebrafish', url => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt' },
		     { name => 'sanger', url => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt' },
		     { name => 'thornton', url => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt' },
		     { name => 'vectorbase', url => 'ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/anopheles_gambiae/VBRNAseq_group_SRP014756/hub.txt',  assemblies => { AgamP4 => 'GCA_000005575.1' } }
		    );

  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  foreach my $hub (@public_hubs) {
    if (head($hub->{url})) {
      note sprintf "Submitting hub %s", $hub->{name};
      my $post = { url => $hub->{url} };
      $post->{assemblies} = $hub->{assemblies} if $hub->{assemblies};
      $request = POST('/api/trackhub?permissive=1',
		      'Content-type' => 'application/json',
		      'Content'      => to_json($post));
      $request->headers->header(user       => 'trackhub1');
      $request->headers->header(auth_token => $auth_token);
      ok($response = request($request), 'POST request to /api/trackhub');
      ok($response->is_success, 'Request successful 2xx');
      is($response->content_type, 'application/json', 'JSON content type');
    }
  }

  # Now register another hub but do not make it available for search
  note sprintf "Submitting hub polyA (not searchable)";
  $request = POST('/api/trackhub?permissive=1',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ url => 'http://johnlab.org/xpad/Hub/UCSC.txt', public => 0 }));
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

  #
  # /api/search endpoint
  #
  # no data
  $request = POST('/api/search',
		  'Content-type' => 'application/json');
  ok($response = request($request), 'POST request to /api/search');
  is($response->code, 400, 'Request unsuccessful 400');
  $content = from_json($response->content);;
  like($content->{error}, qr/Missing/, 'Correct error response');

  # empty query, get all entries
  # default page and entries_per_page
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{total_entries}, 18, 'Number of search results');
  is(scalar @{$content->{items}}, 5, 'Number of search results per page');
  ok($content->{items}[0]{id}, 'Search result item has ID');
  ok($content->{items}[1]{score}, 'Search result item has score');
  ok(!$content->{items}[2]{data}, 'Search results have no metadata');
  ok(!$content->{items}[3]{configuration}, 'Search results have no configuration');

  # test getting the n-th page
  $request = POST('/api/search?page=3',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 5, 'Number of search results per page');

  # test the entries_per_page parameter
  $request = POST('/api/search?page=3&entries_per_page=2',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of entries per page');
  
  # test with query string
  # blueprint hub has some metadata to look for
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => 'monocyte male' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of search results');
  is($content->{items}[0]{hub}{shortLabel}, 'Blueprint Hub', 'Search result hub');
  is($content->{items}[0]{assembly}{accession}, 'GCA_000001405.15', 'Search result assembly');

  $request = POST('/api/search?page=2',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => 'neutrophil' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');
  
  # test with some filters
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ species => 'Danio rerio'}));
  ok($response = request($request), 'POST request to /api/search [filter: Danio rerio (species)');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 4, 'Number of search results');
  is($content->{items}[0]{species}{tax_id}, '7955', 'Search result species');
  ok($content->{items}[0]{hub}{shortLabel} eq 'GRC Genome Issues under Review' ||
     $content->{items}[0]{hub}{shortLabel} eq 'ZebrafishGenomics', 'Search result hub');
  ok($content->{items}[1]{assembly}{name} eq 'GRCz10' || $content->{items}[1]{assembly}{name} eq 'Zv9', 'Search result assembly');
  ok($content->{items}[2]{hub}{longLabel} eq 'Burgess Lab Zebrafish Genomic Resources' ||
     $content->{items}[2]{hub}{longLabel} eq 'Genome Reference Consortium: Genome issues and other features', 'Search result hub');

  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ assembly => 'GRCz10' }));
  ok($response = request($request), 'POST request to /api/search [filter: GRCz10 (assembly)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of search results');
  ok($content->{items}[0]{hub}{shortLabel} eq 'GRC Genome Issues under Review' || $content->{items}[0]{hub}{shortLabel} eq 'ZebrafishGenomics', 'Search result hub');

  # ENSCORESW-2039: could not search we case sensitive assembly parameter
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ assembly => 'AgamP4' }));
  ok($response = request($request), 'POST request to /api/search [filter: AgamP4 (assembly)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  ok($content->{items}[0]{hub}{shortLabel} eq 'Male adult (Tu 2012)', 'Search result hub');
  
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ hub => '454paper' }));
  ok($response = request($request), 'POST request to /api/search [filter: 454paper (hub)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  ok($content->{items}[0]{hub}{longLabel} eq 'Whole-Cell 454 Hela and K562 RNAseq', 'Search result hub');

  # incompatible filters should return no results
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ species  => 'Danio rerio',
					      hub => '454paper'}));
  ok($response = request($request), 'POST request to /api/search [filters: Danio rerio (species), 454paper (hub)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');

  # test search by accession
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ accession  => 'GCA_000002035.3' }));
  ok($response = request($request), 'POST request to /api/search [filters: Danio rerio, GRCh37]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of search results');
  ok($content->{items}[0]{hub}{shortLabel} eq 'GRC Genome Issues under Review' || $content->{items}[0]{hub}{shortLabel} eq 'ZebrafishGenomics', 'Search result hub');
  
  
  
  # search for non public hub should get no results
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ hub => 'xPADHub'}));
  ok($response = request($request), 'POST request to /api/search [filters: xPADHub]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');

  #
  # /api/search/trackdb/:id endpoint
  #
  # non GET request should fail
  $request = POST('/api/search/trackdb/1');
  ok($response = request($request), 'POST request to /api/search/trackdb/:id');
  is($response->code, 405, 'Request unsuccessful 405');

  # get the ID of the trackDB of the miRcode Hub 
  # test hub filter meanwhile
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ hub => 'miRcodeHub'}));
  ok($response = request($request), 'POST request to /api/search [filters: miRcodeHub]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  my $id = $content->{items}[0]{id};
  ok($id, 'Search result has ID');

  $request = GET("/api/search/trackdb/$id");
  ok($response = request($request), 'GET request to /api/search/trackdb/:id');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{hub}{name}, 'miRcodeHub', 'TrackDB hub name');
  is($content->{configuration}{mir_sites_highcons}{bigDataUrl}, 'http://www.mircode.org/ucscHub/hg19/gencode_mirsites_highconsfamilies.bb', 'TrackDB configuration');
  # shouldn't have the metadata
  ok(!$content->{data}, 'No metadata');
  
}

done_testing();
