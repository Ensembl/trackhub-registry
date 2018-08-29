# Copyright [2015-2018] EMBL-European Bioinformatics Institute
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
  my $indexer = Registry::Indexer->new(
            dir   => "$Bin/trackhub-examples/",
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
         # { name => 'mRNA', url => 'http://www.mircode.org/ucscHub/hub.txt' },
         # { name => 'blueprint', url => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub' },
         # { name => 'plants', url => 'http://genome-test.gi.ucsc.edu/~hiram/hubs/Plants/hub.txt' },
         # { name => 'ensembl', url => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt' },
         # { name => 'rnaseq', url => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt' },
         # { name => 'zebrafish', url => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt' },
         { name => 'sanger', url => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt' },
         # { name => 'thornton', url => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt' },
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
  ok($response = request($request), 'POST request to /api/search with blank query');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{total_entries}, 8, 'Number of search results');

  is(scalar @{$content->{items}}, 5, 'Number of search results per page');
  map { is($_->{status}{message}, "Unchecked", "Search result has status") } @{$content->{items}};
  ok($content->{items}[0]{id}, 'Search result item has ID');
  ok($content->{items}[1]{score}, 'Search result item has score');
  ok(!$content->{items}[2]{data}, 'Search results have no metadata');
  ok(!$content->{items}[3]{configuration}, 'Search results have no configuration');

  note("test getting the n-th page");
  $request = POST('/api/search?page=3',
      'Content-type' => 'application/json',
      'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results per page beyond end of results');

  note("test the entries_per_page parameter");
  $request = POST('/api/search?page=3&entries_per_page=2',
      'Content-type' => 'application/json',
      'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of entries per page');

  note("test option to return all results");
  $request = POST('/api/search?all=1',
      'Content-type' => 'application/json',
      'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{total_entries}, 9, 'Number of search results');
  is(scalar @{$content->{items}}, 9, 'Number of search results per page');

  note("when asking for all results, the other parameters should be ignored");
  $request = POST('/api/search?all=1&page=2&entries_per_page=10',
      'Content-type' => 'application/json',
      'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{total_entries}, 9, 'Number of search results');
  is(scalar @{$content->{items}}, 9, 'Number of search results per page');

  note("Test query strings for something that isn't there");
  $request = POST('/api/search?page=2',
      'Content-type' => 'application/json',
      'Content'      => to_json({ query => 'neutrophil' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');
  

### From here things get gnarly. The analyser in Elasticsearch to create a lowercase field for species name
#   does not seem to operate on the test data, but works in a more regular environment

  note("test with filter on species");
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ species => 'Danio rerio'}));
  ok($response = request($request), 'POST request to /api/search [filter: Danio rerio (species)');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of search results');
  my @track_summaries = sort { $a->{id} cmp $b->{id} } @{$content->{items}}; # Deal with random order of return values
  is($track_summaries[0]{species}{tax_id}, '7955', 'Search result species');
  is($track_summaries[0]{hub}{shortLabel}, 'GRC Genome Issues under Review', 'First Zebrafish label correct'); 
  is($track_summaries[1]{assembly}{name}, 'GRCz10','Search result assembly');
  is($track_summaries[1]{hub}{longLabel}, 'Genome Reference Consortium: Genome issues and other features', 'Long form hub label'); 
  
  note("Filter on assembly");
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ assembly => 'GRCz10' }));
  ok($response = request($request), 'POST request to /api/search [filter: GRCz10 (assembly)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  @track_summaries = sort { $a->{id} cmp $b->{id} } @{$content->{items}};
  is($track_summaries[0]{hub}{shortLabel}, 'GRC Genome Issues under Review', 'Search result hub');

  # ENSCORESW-2039:
  note("Search with case sensitive assembly parameter");  
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ assembly => 'AgamP4' }));
  ok($response = request($request), 'POST request to /api/search [filter: AgamP4 (assembly)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  is($content->{items}[0]{hub}{shortLabel}, 'Male adult (Tu 2012)', 'Search result hub');
  
  note("Search by hub");
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ hub => 'VBRNAseq_group_SRP014756' }));
  ok($response = request($request), 'POST request to /api/search [filter: VBRNAseq_group_SRP014756 (hub)]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  is($content->{items}[0]{hub}{longLabel}, 'Male adult <i>Anopheles gambiae</i> from the G3 strain.', 'Search result hub');

  note("test search by accession");
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ accession  => 'GCA_000002035.3' }));
  ok($response = request($request), 'POST request to /api/search [filters: Danio rerio, GRCh37]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  @track_summaries = sort { $a->{id} cmp $b->{id} } @{$content->{items}};
  is($track_summaries[0]{hub}{shortLabel}, 'GRC Genome Issues under Review', 'Search result hub');
  
    
  note("search for non public hub should get no results");
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ hub => 'UltraconservedElements'}));
  ok($response = request($request), 'POST request to /api/search [filters: UltraconservedElements]');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');

  #
  # /api/search/trackdb/:id endpoint
  #
  note("non GET request should fail");
  $request = POST('/api/search/trackdb/1');
  ok($response = request($request), 'POST request to /api/search/trackdb/:id');
  is($response->code, 405, 'Request unsuccessful 405');

  # get the ID of the trackDB of the miRcode Hub 
  # test hub filter meanwhile
  $request = POST('/api/search',
      'Content-type' => 'application/json',
      'Content'      => to_json({ hub => 'VBRNAseq_group_SRP014756'}));
  ok($response = request($request), 'POST request to /api/search [filters: VBRNAseq_group_SRP014756]');
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
  is($content->{hub}{name}, 'VBRNAseq_group_SRP014756', 'TrackDB hub name');
  is($content->{configuration}{'VBRNAseq_group_SRP014756_bigwig'}{members}{'001_VBRNAseq_track_138.bigwig'}{bigDataUrl}, 'ftp://ftp.vectorbase.org/public_data/rnaseq_alignments/hubs/anopheles_gambiae/VBRNAseq_group_SRP014756/AgamP4/../../../../bigwig/anopheles_gambiae/SRP014756_AgamP4.bw', 'TrackDB configuration');
  # shouldn't have the metadata
  ok(!$content->{data}, 'No metadata');

}

done_testing();
