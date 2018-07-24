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
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

use LWP;
use JSON;
use Data::Dumper;

use Registry;
use Registry::Utils; # slurp_file, es_running
use Registry::Indexer;

use_ok 'Registry::Model::Search';

my $es = Registry::Model::Search->new();

isa_ok($es, 'Registry::Model::Search');
is($es->nodes, 'localhost:9200', 'Correct default nodes');

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    6 unless &Registry::Utils::es_running();

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
  $indexer->index_trackhubs();

  # Test pager functionality
  my $list = $es->pager({ 
    body => { query => { match_all => {} } }, 
    index => $config->{trackhub}{index}, 
    type => $config->{trackhub}{type}
  });
  cmp_ok(scalar @$list, '==', 4, 'Get the standard four documents');

  $list = $es->pager({ 
    body => { query => { match_all => {} } }, 
    index => $config->{trackhub}{index}, 
    type => $config->{trackhub}{type}
  }, sub {
      my $doc = shift;
      $doc->{_source}{_injected_stuff} = 1;
      return $doc;
    }
  );
  cmp_ok(scalar @$list, '==', 4, 'Still getting the standard four documents');
  is($list->[-1]->{_source}{_injected_stuff},1,'Callback has added dynamic content to each response');
  is($list->[1]->{_source}{_injected_stuff},1,'Callback has added dynamic content to each response');


  #
  # Now try with size limit smaller than data set
  #
  $list = $es->pager({ 
    body => { query => { match_all => {} } }, 
    index => $config->{trackhub}{index}, 
    type => $config->{trackhub}{type},
    size => 1
  });

  cmp_ok(scalar @$list, '==', 4, 'Get all 4 docs despite limited search size');

  #
  # and size limit coincidentally the same size as the data set
  #
  $list = $es->pager({ 
    body => { query => { match_all => {} } }, 
    index => $config->{trackhub}{index}, 
    type => $config->{trackhub}{type},
    size => 4
  });

  cmp_ok(scalar @$list, '==', 4, 'Get all 4 docs with precise search size');

  #
  # Test search getting all documents
  #
  # - getting all documents: no args
  #
  my $docs = $es->search_trackhubs();
  is(scalar @{$docs->{hits}{hits}}, 4, "Doc counts when requesting all documents match");
  #
  # - getting docs for a certain user: use term filter
  $docs = $es->search_trackhubs(query => { term => { owner => 'trackhub1' } });
  is(scalar @{$docs->{hits}{hits}}, 2, "Doc counts when requesting docs for a certain user");

  $docs = $es->search_trackhubs(query => { term => { owner => 'trackhub3' } });
  is(scalar @{$docs->{hits}{hits}}, 1, "Doc counts when requesting docs for a certain user");


  #
  # Test getting documents by IDs
  #
  # missing arg throws exception
  throws_ok { $es->get_trackhub_by_id }
    qr/Missing/, "Fetch doc without required arguments";

  # getting existing documents
  my $doc = $es->get_trackhub_by_id(1);
  is($doc->{data}[0]{id}, "bpDnaseRegionsC0010K46DNaseEBI", "Fetch correct document");
  
  $doc = $es->get_trackhub_by_id(2);
  is(scalar @{$doc->{data}}, 4, "Fetch correct document");

  # getting document by non-existant ID
  throws_ok { $es->get_trackhub_by_id(5) }
    qr/Missing/, "Request document by incorrect ID";

  # Test count_trackhubs (see Registry::Indexer for test data)
  my $count = $es->count_trackhubs();
  cmp_ok($count, '==', 4, 'Retrieve count of ALL trackhubs');
  $count = $es->count_trackhubs(query => {term => {owner => 'trackhub1'}});
  cmp_ok($count, '==', 2, 'Only one hub belongs to trackhub1');

}

done_testing();
