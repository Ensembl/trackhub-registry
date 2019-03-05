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
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

use JSON;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;
use LWP::Simple qw($ua head);

use Test::WWW::Mechanize::Catalyst;
use Search::Elasticsearch::TestServer;
use Search::Elasticsearch;

my $es_server = Search::Elasticsearch::TestServer->new( es_version => '6_0');
my $es_nodes = $es_server->start();

my $INDEX_NAME = 'trackhubs'; # Matches registry_testing.conf
my $INDEX_TYPE = 'trackdb';

use Catalyst::Test 'Registry';

use Registry::Utils;

my $es_client = Search::Elasticsearch->new(
  nodes => $es_nodes
);
my $hub_content = slurp_file("$Bin/track_hub/plant1.json");
# Populate some hubs so we can test the search box interface
$es_client->index(
  index => $INDEX_TYPE,
  index_name => $INDEX_TYPE,
  body => $hub_content
);



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
$mech->content_like(qr/Unintelligible query string/s, 'Query parsing failed');
# Submit with a plain search string
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => 'GRC ALT align'
    }
  }, 'Plain text query for something in the Sanger trackhub');
$mech->content_like(qr/GRC Genome Issues under Review/s, 'Results contain some useful representative hits');

# Submit with a qualified search string
# It would be really great if we could get rid of these brackets without needing to rebuild the query object
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => 'species.scientific_name:(Mus musculus)'
    }
  }, 'Qualified species constraint query for something in the Sanger trackhub');
# Note capitalisation of species is critical. An additional analysed field is created called 
# species.scientific_name.lowercase for case-insensitive searches
$mech->content_like(qr/GRC Genome Issues under Review/s, 'Results contain some useful representative hits');

# Try a mixed query, of named fields and general text strings
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => 'species.scientific_name:(Mus musculus) AND GRC Genome Issues under Review'
    }
  }, 'Qualified species constraint query for something in the Sanger trackhub');
# Note capitalisation of species is critical. An additional analysed field is created called 
# species.scientific_name.lowercase for case-insensitive searches
$mech->content_like(qr/mm9/s, 'Results contain some useful representative hits');

# Try a query with no text. Should match all public hubs.
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => undef
    }
  }, 'match_all query fires when no query is provided');
$mech->content_like(qr/Track Collections 1 to 5 of 7/s, 'Results of match_all are correct in number and pagination');

done_testing();
