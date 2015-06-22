use strict;
use warnings;
use Test::More;

use JSON;
use HTTP::Request::Common qw/GET POST/;
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use Catalyst::Test 'Registry';

use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

SKIP: {
  skip "Cannot run tests: either elasticsearch is not running or there's no internet connection",
    3 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();

  note 'Preparing data for test (indexing users)';
  my $config = Registry->config()->{'Model::Search'};
  my $indexer = Registry::Indexer->new(dir   => "$Bin/trackhub-examples/",
						index => $config->{index},
						trackhub => {
						  type  => $config->{type}{trackhub},
						  mapping => 'trackhub_mappings.json'
						},
						authentication => {
						  type  => $config->{type}{user},
						  mapping => 'authentication_mappings.json'
						}
					       );

  # index sample hubs/users
  $indexer->index_trackhubs();
  $indexer->index_users();

  # no data
  my $request = POST('/api/search',
		     'Content-type' => 'application/json');
  ok(my $response = request($request), 'POST request to /api/search');
  is($response->code, 400, 'Request unsuccessful 400');
  my $content = from_json($response->content);;
  like($content->{error}, qr/Missing/, 'Correct error response');

  $request = POST('/api/search',
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  
}

done_testing();
