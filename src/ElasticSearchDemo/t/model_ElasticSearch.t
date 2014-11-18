use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use LWP;
use JSON;
use Data::Dumper;

use ElasticSearchDemo::Utils; # slurp_file, es_running
use ElasticSearchDemo::Indexer;

use_ok 'ElasticSearchDemo::Model::ElasticSearch';

my $es = ElasticSearchDemo::Model::ElasticSearch->new();

isa_ok($es, 'ElasticSearchDemo::Model::ElasticSearch');
is($es->nodes, 'localhost:9200', 'Correct default nodes');

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    6 unless &ElasticSearchDemo::Utils::es_running();

  my $indexer = ElasticSearchDemo::Indexer->new(dir   => "$Bin/../../../docs/trackhub-schema/draft02/examples/",
						index => 'test',
						trackhub => {
						  type  => 'trackhub',
						  mapping => 'trackhub_mappings.json'
						},
						authentication => {
						  type  => 'user',
						  mapping => 'authentication_mappings.json'
						}
					       );
  $indexer->index_trackhubs();
  $indexer->index_users();

  my $es = ElasticSearchDemo::Model::ElasticSearch->new();

  #
  # Test getting all documents
  #
  # no args default to get all docs
  #
  my $docs = $es->query(type => 'trackhub');
  is(scalar @{$docs->{hits}{hits}}, 4, "Doc counts when requesting all documents match");

  #
  # Test getting documents by IDs
  #
  # missing args throws exception
  my %args;   
  throws_ok { $es->find(%args) }
    qr/Missing/, "Fetch doc without required arguments";
  $args{index} = 'test';
  $args{id} = 1;
  throws_ok { $es->find(%args) }
    qr/Missing/, "Fetch doc without required arguments";

  # getting existing documents
  $args{id} = 1;
  $args{type} = 'trackhub';
  my $doc = $es->find(%args);
  is($doc->{data}[0]{name}, "bpDnaseRegionsC0010K46DNaseEBI", "Fetch correct document");
  
  $args{id} = 2;
  $doc = $es->find(%args);
  is(scalar @{$doc->{data}}, 4, "Fetch correct document");

  # getting document by non-existant ID
  $args{id} = 5;
  throws_ok { $es->find(%args) }
    qr/Missing/, "Request document by incorrect ID"
}

done_testing();
