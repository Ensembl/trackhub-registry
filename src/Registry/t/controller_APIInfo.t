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
use List::Util qw( first );
use HTTP::Request::Common qw/GET POST/;
use Data::Dumper;
use LWP::Simple qw($ua head);

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use Catalyst::Test 'Registry';

use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

my $request = GET('/api/info/version');
ok(my $response = request($request), 'GET request to /api/info/version');
ok($response->is_success, 'Request successful');
my $content = from_json($response->content);
is($content->{release}, $Registry::VERSION, "API current version is $Registry::VERSION");

SKIP: {
  skip "Cannot run tests: either elasticsearch is not running or there's no internet connection",
    62 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();
  
  # /api/info/ping
  my $request = GET('/api/info/ping');
  ok(my $response = request($request), 'GET request to /api/info/ping');
  ok($response->is_success, 'Request successful');
  my $content = from_json($response->content);
  ok($content->{ping}, 'Service available');

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
         # { name => 'blueprint', url => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub' },
         { name => 'plants', url => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt' },
         { name => 'ensembl', url => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt' },
         { name => 'rnaseq', url => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt' },
         { name => 'zebrafish', url => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt' },
         { name => 'sanger', url => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt' },
         # NA any more { name => 'thornton', url => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt' }, 
        );

  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  $ua->timeout(10);
  foreach my $hub (@public_hubs) {
    if (head($hub->{url})) {
      note sprintf "Submitting hub %s", $hub->{name};
      $request = POST('/api/trackhub?permissive=1',
          'Content-type' => 'application/json',
          'Content'      => to_json({ url => $hub->{url} }));
      $request->headers->header(user       => 'trackhub1');
      $request->headers->header(auth_token => $auth_token);
      ok($response = request($request), 'POST request to /api/trackhub');
      ok($response->is_success, 'Request successful 2xx for '.$hub->{name}.' hub');
      is($response->content_type, 'application/json', 'JSON content type');
    } else{
      note sprintf "WARN: Skipping hub %s ", $hub->{name}, " Please remove it from the public_hubs list"; 
    }
  }

  #
  # /api/info/species endpoint
  #
  my %species_assemblies = 
    ( 'Homo sapiens'         => [
         { name => 'GRCh37', synonyms => [ 'hg19' ], accession => 'GCA_000001405.1' },
         { name => 'GRCh38', synonyms => [ 'hg38' ], accession => 'GCA_000001405.15' }
        ],
      'Danio rerio'          => [
         { name => 'GRCz10', synonyms => [ 'danrer10' ], accession => 'GCA_000002035.3' },
         { name => 'Zv9', synonyms => [ 'danrer7' ], accession => 'GCA_000002035.2' }
        ],
      'Mus musculus'         => [
         { name => 'GRCm38', synonyms => [ 'mm10' ], accession => 'GCA_000001635.2' },
         { name => 'MGSCv37', synonyms => [ 'mm9' ], accession => 'GCA_000001635.1' }
        ], 
      'Arabidopsis thaliana' => [ { name => 'TAIR10', synonyms => [ 'aratha1' ], accession => 'GCA_000001735.1' } ],
      'Brassica rapa'        => [ { name => 'Brapa_1.0', synonyms => [ 'brarap1' ], accession => 'GCA_000309985.1' } ],
      #'Drosophila simulans'  => ['GCA_000754195.2'], 
      'Ricinus communis'     => [ { name => 'JCVI_RCG_1.1', synonyms => [ 'riccom1' ], accession => 'GCA_000151685.2' } ]);

  $request = GET('/api/info/species');
  ok($response = request($request), 'GET request to /api/info/species');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is_deeply([ sort @{$content} ], [ sort keys %species_assemblies ], 'List of species');

  #
  # /api/info/assemblies endpoint
  #
  $request = GET('/api/info/assemblies');
  ok($response = request($request), 'GET request to /api/info/assemblies');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is_deeply([ sort keys %{$content} ], [ sort keys %species_assemblies ], 'List of species');
  foreach my $species (keys %{$content}) {
    is_deeply($content->{$species}, $species_assemblies{$species}, "Assemblies for species $species");
  }

  #
  # /api/info/trackhubs
  #
  $request = GET('/api/info/trackhubs');
  ok($response = request($request), 'GET request to /api/info/trackhubs');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  #is(scalar @{$content}, scalar @public_hubs, 'Number of hubs'); #excluding polyA and thornton
  is(scalar @{$content}, 6, 'Number of hubs');

  # test a couple of hubs
  my $hub = first { $_->{name} eq 'EnsemblRegulatoryBuild' } @{$content};
  ok($hub, 'Ensembl regulatory build hub');
  is($hub->{longLabel}, 'Evidence summaries and provisional results for the new Ensembl Regulatory Build', 'Hub longLabel');
  is(scalar @{$hub->{trackdbs}}, 3, 'Number of trackDbs');
  map { ok($_->{species} == 9606 || $_->{species} == 10090, "trackDb species") } @{$hub->{trackdbs}};
  map { like($_->{assembly}, qr/GCA_000001405|GCA_000001635/, 'trackDb assembly') } @{$hub->{trackdbs}};
  map { like($_->{uri}, qr/api\/search\/trackdb/, 'trackDb uri') } @{$hub->{trackdbs}};

  $hub = first { $_->{name} eq 'NHGRI-1' } @{$content};
  ok($hub, 'Zebrafish hub');
  is($hub->{shortLabel}, 'ZebrafishGenomics', 'Hub shortLabel');
  is(scalar @{$hub->{trackdbs}}, 2, 'Number of trackDbs');
  is($hub->{trackdbs}[0]{species}, 7955, 'trackDb species');
  like($hub->{trackdbs}[0]{assembly}, qr/^GCA_000002035.\d$/, 'trackDb assembly');
  like($hub->{trackdbs}[0]{uri}, qr/api\/search\/trackdb/, 'trackDb uri');

  #
  # /api/info/hubs_per_assembly
  #
  # test with accession
  $request = GET('/api/info/hubs_per_assembly/GCA_000001405.15');
  ok($response = request($request), 'GET request to /api/info/hubs_per_assembly');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is($content->{tot}, 2, 'Number of hubs per assembly');
  #
  # test with assembly name
  $request = GET('/api/info/hubs_per_assembly/GRCh38');
  ok($response = request($request), 'GET request to /api/info/hubs_per_assembly');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is($content->{tot}, 2, 'Number of hubs per assembly');
  
  #
  # /api/info/tracks_per_assembly
  #
  # test with accession
  $request = GET('/api/info/tracks_per_assembly/GCA_000001405.15');
  ok($response = request($request), 'GET request to /api/info/tracks_per_assembly');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is($content->{tot}, 166, 'Number of tracks per assembly');
  #
  # test with assembly name
  $request = GET('/api/info/tracks_per_assembly/GRCh38');
  ok($response = request($request), 'GET request to /api/info/tracks_per_assembly');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is($content->{tot}, 166, 'Number of tracks per assembly');
}

done_testing();
