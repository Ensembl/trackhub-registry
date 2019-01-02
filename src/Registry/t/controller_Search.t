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

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;
use LWP::Simple qw($ua head);

use Test::WWW::Mechanize::Catalyst;
use Catalyst::Test 'Registry';

use Registry::Utils;
use Registry::Indexer;

SKIP: {
  skip "Cannot run tests: either elasticsearch is not running or there's no internet connection",
    5 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();

  note 'Preparing data for test (indexing users)';
  my $config = Registry->config()->{'Model::Search'};
  my $indexer = Registry::Indexer->new( dir   => "$Bin/trackhub-examples/",
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

  # index sample users
  $indexer->index_users();

  # authenticate one of them
  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  # submit public hubs (from UCSC list)
  # 10 out of 27 hubs cannot be submitted
  # - 1, unknown (memory/CPU issue)
  # - 3, tracks do not refer to parent
  # - 6, empty type attribute
  # - 1, unknown assembly synonyms
  
  # sdsu: empty type - does not validate if empty fields are not allowed. There's one track which does not define type, the parser attempts to define type based on bigDataUrl, which is not defined as well. Can be solved by removing empty attributes in Translator
  # zhub: empty type
  # washu: empty type
  # cptac: empty type
  # facebase: empty type, but also track names contain '.'. cannot enforce it in the schema, solved by allowing additional properties for the configuration object
  # libd: track names contain '-' which is not in the schema (solved)
  # cemt: goes into timeout -> increase (solved)
  my %public_hubs = (
     vizhub  => 'http://vizhub.wustl.edu/VizHub/RoadmapReleaseAll.txt', # memory/CPU consumption, empty type (memory/CPU issue solved by printing just the error in the validation script)
     # zhub    => 'http://zlab.umassmed.edu/zlab/publications/UMassMedZHub/hub.txt', # empty type, do not exist any more
     polyA   => 'http://johnlab.org/xpad/Hub/UCSC.txt',
     encode  => 'http://ftp.ebi.ac.uk/pub/databases/ensembl/encode/integration_data_jan2011/hub.txt',
     mRNA    => 'http://www.mircode.org/ucscHub/hub.txt',
     # dnameth => 'http://smithlab.usc.edu/trackdata/methylation/hub.txt', #Comment: Unable to find a valid INSDC accession for genome assembly name tair10
     tis     => 'http://gengastro.1med.uni-kiel.de/suppl/footprint/Hub/tisHub.txt',
     sdsu    => 'http://bioinformatics.sdstate.edu/datasets/2012-NAT/hub.txt', # empty type
     blueprint => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub',
     # cemt      => 'http://www.bcgsc.ca/downloads/edcc/data/CEMT/hub/bcgsc_datahub.txt', # redirects to another location
     plants    => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt',
     # broad     => 'https://www.broadinstitute.org/ftp/pub/vgb/dog/trackHub/hub.txt', # parent track is missing
     ensembl   => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt',
     mcgill    => 'http://epigenomesportal.ca/hub/hub.txt',
     ultracons => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/GillBejerano/hub.txt',
     # fantom5   => 'http://fantom.gsc.riken.jp/5/datahub/hub.txt', # parent track missing
     washu     => 'http://vizhub.wustl.edu/VizHub/RoadmapIntegrative.txt', # empty type
     rnaseq    => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt',
     zebrafish => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt',
     # facebase  => 'http://trackhub.facebase.org/hub.txt', # empty type, track name with '.', do not exist any more
     phylocsf  => 'http://www.broadinstitute.org/compbio1/PhyloCSFtracks/trackHub/hub.txt',
     # fantom5c  => 'http://fantom.gsc.riken.jp/5/suppl/Ohmiya_et_al_2014/data/hub.txt', # parent track missing
     sanger    => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt',
     # crocbird  => 'http://hgwdev.cse.ucsc.edu/~jcarmstr/crocBrowserRC2/hub.txt', # unknown assembly Anc00 -- Anc21
     thornton  => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt',
     cptac     => 'http://openslice.fenyolab.org/tracks/CPTAC/cptac/v1/hub.txt', # empty type
     libd      => 'https://s3.amazonaws.com/DLPFC_n36/humanDLPFC/hub.txt',
    );

  $ua->timeout(10);
  # foreach my $hub (keys %public_hubs) {
  #   note "Submitting hub $hub";
  #   if (head($public_hubs{$hub})) {
  #     my $request = POST('/api/trackhub?permissive=1',
  #              'Content-type' => 'application/json',
  #              'Content'      => to_json({ url => $public_hubs{$hub} }));
  #     $request->headers->header(user       => 'trackhub1');
  #     $request->headers->header(auth_token => $auth_token);
  #     ok($response = request($request), 'POST request to /api/trackhub/create');
  #     ok($response->is_success, 'Request successful 2xx');
  #     is($response->content_type, 'application/json', 'JSON content type');
  #   }else{
  #      note "Submitting hub $hub timed out. Please check the url $public_hubs{$hub})\n";
  #   }
  # }

  # [ENSCORESW-2121]
  # check unexpected characters in query are appropriately handled
  my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');
  $mech->get_ok('/', 'Requested main page');
  $mech->submit_form_ok({
                         form_number => 1,
                         fields      => {
                           q => '/'
                         },
                        }, 'Submit wrong character as search query'
                             );
  $mech->content_like(qr/An unexpected error happened.*?No results/s, 'Query parsing failed');

}

done_testing();
