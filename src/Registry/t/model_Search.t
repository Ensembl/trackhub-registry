# Copyright [2015-2023] EMBL-European Bioinformatics Institute
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
}

use LWP;
use JSON;

use Registry::Utils; # slurp_file, es_running
use Search::Elasticsearch::TestServer;
use Test::MockObject;

use_ok 'Registry::Model::Search';


my $es_nodes = '127.0.0.1:9200';
my $INDEX_NAME = 'trackhub_test';
my $INDEX_TYPE = 'trackdb'; # Don't change this. It needs to match the mappings in the mapping_file below

my $model = Registry::Model::Search->new(
  nodes => $es_nodes,
  schema => {
    trackhub => {
      mapping_file => "$Bin/../../../docs/trackhub-schema/v1.0/trackhub_mappings.json",
      index_name => $INDEX_NAME,
      type => $INDEX_TYPE
    }
  }
);

isa_ok($model, 'Registry::Model::Search');

my %test_hub_content = (
  type => 'epigenomics',
  owner => 'user1',
  public => 'true',
  hub => {
    name => 'Blueprint_Hub',
    shortLabel => 'Blueprint Hub',
    longLabel => 'Blueprint Epigenomics Data Hub',
    url => 'file:///test/blueprint1'
  },
  species => {
    tax_id => 9606,
    scientific_name => 'Homo sapiens'
  },
  assembly => {
    accession => 'GCA_000001405.1',
    name => 'GRCh37',
    synonyms => 'hg19'
  },
  data => [{
    id => 'bob',
    random_key => 'surprise'
  }],
  configuration => {
    bob => {
      shortLabel => 'testing',
      longLabel => 'Example track',
      visibility => 'full',
      bigDataUrl => 'http://does.not.matter/',
      type => 'bigbed',
    }
  }
);

my %secondary_test_hub_content = (
  type => 'epigenomics',
  owner => 'user2',
  public => 'true',
  hub => {
    name => 'a_hub',
    shortLabel => 'a',
    longLabel => 'a contrived test',
    url => 'file:///test/a'
  },
  species => {
    tax_id => 9606,
    scientific_name => 'Homo sapiens'
  },
  assembly => {
    accession => 'GCA_000001405.1',
    name => 'GRCh37',
    synonyms => 'hg19'
  },
  data => [{
    id => 'trev',
    random_key => 'surprise'
  }],
  configuration => {
    bob => {
      shortLabel => 'testing',
      longLabel => 'Example track',
      visibility => 'full',
      bigDataUrl => 'http://does.not.matter/',
      type => 'bigbed',
    }
  }
);

note 'Populate schemas to test DB';
$model->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => \%test_hub_content
);

$model->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => \%secondary_test_hub_content
);

# Any new document is not immediately available for searching without a transaction commit
$model->indices->refresh;

# Test pager functionality
my $list = $model->pager({ 
  query => { match_all => {} }
});
cmp_ok(scalar @$list, '==', 2, 'Get both documents via unrestricted search');

my %relevant_content;
if ($list->[0]{_source}{hub}{name} eq 'a_hub') {
  %relevant_content = %secondary_test_hub_content;
} else {
  %relevant_content = %test_hub_content;
}

is_deeply($list->[0]{_source}, \%relevant_content, 'Check fields were stored in the backend');

# Test callback functionality
$list = $model->pager({
  query => { match_all => {} }
}, sub {
    my $doc = shift;
    $doc->{_source}{_injected_stuff} = 1;
    return $doc;
  }
);
cmp_ok(scalar @$list, '==', 2, 'Still getting both documents');
is($list->[-1]->{_source}{_injected_stuff}, 1, 'Callback has added dynamic content to last response');
is($list->[1]->{_source}{_injected_stuff}, 1, 'Callback has added dynamic content to first response');

#
# Now try with size limit smaller than data set
# The first page of results cannot be properly limited
$list = $model->pager({ 
  query => { match_all => {} },
  size => 1
});

cmp_ok(scalar @$list, '==', 2, 'Get both docs despite limited search size');

#
# and size limit coincidentally the same size as the data set
#
$list = $model->pager({ 
  query => { match_all => {} },
  size => 2
});

cmp_ok(scalar @$list, '==', 2, 'Get both docs with precise search size');

#
# Test search model interface for getting all documents
#
# - getting all documents: no args
#
my $docs = $model->search_trackhubs();
is(scalar @{$docs->{hits}{hits}}, 2, 'Doc counts when requesting all documents match');

my ($DOC_ID, $DOC_ID2) =
  map { $_->{_id} }
  sort { $a->{_source}{owner} cmp $b->{_source}{owner}}
  @{ $docs->{hits}{hits} };

note 'Pulled out ID: '.$DOC_ID.', '.$DOC_ID2;
#
# - getting docs for a certain user: use term filter
$docs = $model->search_trackhubs(query => { term => { owner => 'user1' } });
is(scalar @{$docs->{hits}{hits}}, 1, 'user1 owns one hub');

$docs = $model->search_trackhubs(query => { term => { owner => 'user2' } });
is(scalar @{$docs->{hits}{hits}}, 1, 'user2 owns one hub');


#
# Test getting documents by IDs
#
# missing arg throws exception
throws_ok { $model->get_trackhub_by_id }
  qr/Cannot get a hub without an ID/, 'Fetch doc without required arguments';

# getting existing documents
my $doc = $model->get_trackhub_by_id($DOC_ID);
is($doc->{_source}{data}[0]{id}, 'bob', 'Fetch correct document');

$doc = $model->get_trackhub_by_id($DOC_ID2);
is($doc->{_source}{data}[0]{id}, 'trev', 'Fetch second document by _id');

# getting document by non-existant ID
throws_ok { $model->get_trackhub_by_id(5) }
  qr/Unable to get hub with id 5/, 'Request document by incorrect ID';

# Counting method
my $count = $model->count_trackhubs();
cmp_ok($count, '==', 2, 'Retrieve count of ALL trackhubs');
$count = $model->count_trackhubs(query => {term => {owner => 'user1'}});
cmp_ok($count, '==', 1, 'Only one hub belongs to user1');


# 
# Test canned queries for pre-existing hubs
# 

$count = $model->count_existing_hubs('user1','Blueprint_Hub','GCA_000001405.1');
cmp_ok($count, '==', 1, 'Count instances of a hub owned by a known user');

$count = $model->count_existing_hubs('user2','Blueprint_Hub','GCA_000001405.15');
cmp_ok($count, '==', 0, 'Count instances of a hub owned by a different user');
# these counts are inaccurate. Can't/won't figure out why

$count = $model->count_existing_hubs('user1','totallynothere','GCA_000001405.15');
cmp_ok($count, '==', 0, 'Count instances of a non-existent hub from the same user');

$list = $model->get_existing_hubs('user1','Blueprint_Hub','GCA_000001405.1');
cmp_ok(scalar @$list, '==', 1, 'The list of results is still one long');

is($list->[0]->{_id},$DOC_ID, "Document ID of trackhub1's blueprint hub is consistent");
is($list->[0]->{_source}{owner},'user1', "Owner of user1's blueprint hub is correct");

$list = $model->get_hub_by_url('file:///test/blueprint1');
cmp_ok(@{$list}, '==', 1, 'One hub has the supplied URL');

is($list->[0]->{_id},$DOC_ID, 'Same result, but via trackhub URL. Hub is consistent');
is($list->[0]->{_source}{owner},'user1', "Same result, but via trackhub URL. Owner is correct");


#
# Test pagination function
#

ok ( ! defined (
    $model->paginate({ hits => { total => 0 }}, 1, 5, 0 )
  ),
  'Test a zero hit result'
);

# Single result with per-page value higher than number of results
my %paginated = $model->paginate(
  { 
    hits => {
      total => 1,
      hits => [{ thing => 'here'}]
    }
  }, # result set
  1, # page
  5, # hits per page
  0  # offset
);

ok (! defined $paginated{first_page}, 'First hit, first page, no first page link required');
ok (! defined $paginated{last_page}, 'First hit, first page AND last page, no last page link required');
ok (! defined $paginated{prev_page}, 'First hit, first page, no previous page link required');
ok (! defined $paginated{next_page}, 'Googlewhack, first page, no next page required');
cmp_ok ($paginated{from}, '==', 1, 'One record starting at one');
cmp_ok ($paginated{to}, '==', 1, 'One record ends at one');
cmp_ok ($paginated{page}, '==', 1, 'On page one');
cmp_ok ($paginated{total}, '==', 1, 'Should only be one thing');
cmp_ok ($paginated{page_size}, '==', 5, 'Page size goes in and comes out again');

# Three results on second page with one per page
%paginated = $model->paginate(
  { 
    hits => {
      total => 3,
      hits => [{ thing => 'here'}]
    }
  }, # result set
  2, # page
  1, # hits per page
  1  # offset
);

cmp_ok ($paginated{first_page}, '==', 1, 'Second hit, second page, first page link required');
cmp_ok ($paginated{last_page}, '==', 3, 'Second hit, second page, third page is last');
cmp_ok ($paginated{prev_page}, '==', 1, 'Second hit, second page, previous page link required');
cmp_ok ($paginated{next_page}, '==', 3, 'Second hit, second page, next page required');
cmp_ok ($paginated{from}, '==', 2, 'Record starting at two');
cmp_ok ($paginated{to}, '==', 2, 'Page ends as well as starts at two');
cmp_ok ($paginated{page}, '==', 2, 'On page two');
cmp_ok ($paginated{total}, '==', 3, 'Three things this time');
cmp_ok ($paginated{page_size}, '==', 1, 'Page size goes in and comes out again');

# Three results on third page with one per page
%paginated = $model->paginate(
  { 
    hits => {
      total => 3,
      hits => [{ thing => 'here'}]
    }
  }, # result set
  3, # page
  1, # hits per page
  2  # offset
);

cmp_ok ($paginated{first_page}, '==', 1, 'Third hit, third page, first page link required');
ok (! defined $paginated{last_page}, 'Third hit, third page, no last page');
cmp_ok ($paginated{prev_page}, '==', 2, 'Third hit, third page, previous page link required');
ok (! defined $paginated{next_page}, 'Third hit, third page, next page absent');
cmp_ok ($paginated{from}, '==', 3, 'Record starting at three');
cmp_ok ($paginated{to}, '==', 3, 'Page ends as well as starts at three');
cmp_ok ($paginated{page}, '==', 3, 'On page three');
cmp_ok ($paginated{total}, '==', 3, 'Three things this time');
cmp_ok ($paginated{page_size}, '==', 1, 'Page size goes in and comes out again');

# Multiple hits per page
%paginated = $model->paginate(
  { 
    hits => {
      total => 20,
      hits => [{ thing => 'here'}, { what => 'how?'} ]
    }
  }, # result set
  1, # page
  2, # hits per page
  0  # offset
);

ok (! defined $paginated{first_page}, 'First hits, first page, no first page link required');
cmp_ok ($paginated{last_page}, '==', 10, 'first hits, page one, tenth page is last');
ok (! defined $paginated{prev_page}, 'First page, no previous page link required');
cmp_ok ($paginated{next_page}, '==', 2, 'First page, next page required');
cmp_ok ($paginated{from}, '==', 1, 'Record starting at one');
cmp_ok ($paginated{to}, '==', 2, 'Two things in page one');
cmp_ok ($paginated{page}, '==', 1, 'On page one');
cmp_ok ($paginated{total}, '==', 20, 'Twenty things this time');
cmp_ok ($paginated{page_size}, '==', 2, 'Page size goes in and comes out again');

# Test stats retrieval

my ($hub_count, $species_count, $assembly_count) = $model->stats_query();

cmp_ok($hub_count, '==', 2, 'Stats count of hub total');
cmp_ok($species_count, '==', 1, 'Stats count of species total');
cmp_ok($assembly_count, '==', 1, 'Stats count of assembly total');

# Test track info collection routine
# Mock the URL checker to ensure we get a success result while offline
my $mock_module;
BEGIN {
  $mock_module = Test::MockObject->new();
  $mock_module->fake_module('Registry::Utils::URL', file_exists => sub {return {success => 1} });
};

is_deeply(Registry::Utils::URL::file_exists, {success => 1}, 'Mocking ready');

my $info = $model->_collect_track_info($test_hub_content{configuration});

is($info->{track_total}, 1 ,'Track total established');
is_deeply($info->{number_file_types}, { bigbed => 1 } ,'Track total established');
is($info->{total_tracks_with_data}, 1, 'Mocked URL check successful');
is($info->{broken_track_total}, 0, 'Mocked URL check reports no broken tracks');
is_deeply($info->{error}, {}, 'No errors in the error accumulator');

my %tertiary_test_hub_content = (
  type => 'epigenomics',
  owner => 'user2',
  public => 'true',
  hub => {
    name => 'a_hub',
    shortLabel => 'a',
    longLabel => 'a contrived test',
    url => 'file:///test/a'
  },
  species => {
    tax_id => 9606,
    scientific_name => 'Homo sapiens'
  },
  assembly => {
    accession => 'GCA_000001405.1',
    name => 'GRCh37',
    synonyms => 'hg19'
  },
  data => [{
    id => 'trev',
    random_key => 'surprise'
  }],
  configuration => {
    bob => {
      shortLabel => 'testing',
      longLabel => 'Example track',
      visibility => 'full',
      bigDataUrl => 'http://does.not.matter/',
      type => 'bigbed',
      members => {
        trev => {
          shortLabel => 'testing',
          longLabel => 'Example track',
          visibility => 'full',
          bigDataUrl => 'http://does.not.matter/',
          type => 'bigbed',
        }
      }
    }
  }
);

$model->index(
  index => $INDEX_NAME,
  type => $INDEX_TYPE,
  body => \%tertiary_test_hub_content
);
$model->indices->refresh;

$info = $model->_collect_track_info($tertiary_test_hub_content{configuration});

is($info->{track_total}, 2 ,'Recursive track total established');
is_deeply($info->{number_file_types}, { bigbed => 2 } ,'Track total established');
is($info->{total_tracks_with_data}, 2, 'Mocked URL check successful');
is($info->{broken_track_total}, 0, 'Mocked URL check reports no broken tracks');
is_deeply($info->{error}, {}, 'No errors in the error accumulator');


# Post-test clean-up
$model->indices->delete(index => $INDEX_NAME);

done_testing();
