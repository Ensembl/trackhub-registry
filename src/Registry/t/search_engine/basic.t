use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../../registry_testing.conf";
}

use LWP;
use JSON;
use Data::Dumper;

use Registry::Utils; # slurp_file, es_running
use Registry::Indexer;

use_ok 'Data::SearchEngine::ElasticSearch';

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    6 unless &Registry::Utils::es_running();

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
  $indexer->index_trackhubs();

  my $es = Data::SearchEngine::ElasticSearch->new();
  isa_ok($es, "Data::SearchEngine::ElasticSearch");
  is($es->nodes, '127.0.0.1:9200', 'Correct default nodes');

  
  
}

done_testing();
