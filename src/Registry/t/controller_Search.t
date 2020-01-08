# Copyright [2015-2020] EMBL-European Bioinformatics Institute
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
use Registry::Utils;

use Test::WWW::Mechanize::Catalyst;
use Search::Elasticsearch;

my $es_nodes = '127.0.0.1:9200';
my $es_client = Search::Elasticsearch->new(
  nodes => $es_nodes
);
ok ($es_client->cluster->health, 'ES server waiting');

my $INDEX_NAME = 'trackhubs'; # Matches registry_testing.conf
my $INDEX_TYPE = 'trackdb';

use Catalyst::Test 'Registry';
# Poke the bear
my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'Registry');
$mech->get_ok('/', 'Requested main page');

$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => undef
    }
  }, 'Trigger particularly lazy builds');

my $hub_content = decode_json(Registry::Utils::slurp_file("$Bin/track_hub/plant1.json"));
$hub_content->{public} = JSON::true;
# Populate some hubs so we can test the search box interface
$es_client->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => $hub_content
);
$es_client->indices->refresh(index => $INDEX_NAME);

# [ENSCORESW-2121]
# check unexpected characters in query are appropriately handled
$mech->submit_form_ok(
  {
   form_number => 1,
   fields      => {
     q => '/'
   },
  },
  'Submit a bad character in search box'
); # Slashes upset the Elasticsearch query parser
$mech->content_like(qr/Unintelligible query string/s, 'Query parsing failed');

# Submit with a plain search string
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => 'Biology of Genomes'
    }
  }, 'Plain text query for something in the plant1 hub');
$mech->content_like(qr/Plants/s, 'Results contain relevant hits');

# Submit with a qualified search string
# It would be really great if we could get rid of these brackets without needing to rebuild the query object
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => 'species.scientific_name:(Ricinus communis)'
    }
  }, 'Qualified species constraint query for something in the plant1.json hub');

# Note capitalisation of species is critical. An additional analysed field is created called 
# species.scientific_name.lowercase for case-insensitive searches
$mech->content_like(qr/Plants/s, 'Results contain relevant hits');

# Try a mixed query, of named fields and general text strings
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => 'species.scientific_name:(Ricinus communis) AND Biology of Genomes'
    }
  }, 'Qualified species constraint query');
# Note capitalisation of species is critical. An additional analysed field is created called 
# species.scientific_name.lowercase for case-insensitive searches
$mech->content_like(qr/Plants/s, 'Results contain the relevant hub');

# Try a query with no text. Should match all public hubs.
$mech->submit_form_ok({
    form_number => 1,
    fields => {
      q => undef
    }
  }, 'match_all query fires when no query is provided');

$mech->content_like(qr/Track Collections 1 to 1 of 1/s, 'Results of match_all have correct number and pagination');

$es_client->indices->delete(index => $INDEX_NAME);

done_testing();
