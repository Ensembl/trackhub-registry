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
  $indexer->index_users();

  # submit some public hubs
    my %public_hubs = (
		     polyA   => 'http://johnlab.org/xpad/Hub/UCSC.txt',
		     mRNA    => 'http://www.mircode.org/ucscHub/hub.txt',
		     blueprint => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub',
		     plants    => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt',
		     ensembl   => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt',
		     rnaseq    => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt',
		     zebrafish => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt',
		     sanger    => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt',
		     thornton  => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt',
		    );

  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  foreach my $hub (keys %public_hubs) {
    note "Submitting hub $hub";
    $request = POST('/api/trackhub/create',
		    'Content-type' => 'application/json',
		    'Content'      => to_json({ url => $public_hubs{$hub} }));
    $request->headers->header(user       => 'trackhub1');
    $request->headers->header(auth_token => $auth_token);
    ok($response = request($request), 'POST request to /api/trackhub/create');
    ok($response->is_success, 'Request successful 2xx');
    is($response->content_type, 'application/json', 'JSON content type');
  }

  # no data
  $request = POST('/api/search',
		     'Content-type' => 'application/json');
  ok($response = request($request), 'POST request to /api/search');
  is($response->code, 400, 'Request unsuccessful 400');
  my $content = from_json($response->content);;
  like($content->{error}, qr/Missing/, 'Correct error response');

  # empty query, get all entries
  # default page and entries_per_page
  $request = POST('/api/search',
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{total_entries}, 17, 'Number of search results');
  is(scalar @{$content->{items}}, 5, 'Number of search results per page');
  is($content->{items}[1]{values}{hub}{longLabel}, 'Burgess Lab Zebrafish Genomic Resources', 'Search result hub');
  is($content->{items}[3]{values}{assembly}{name}, 'GRCh38', 'Search result assembly');

  # test getting the n-th page
  $request = POST('/api/search?page=3',
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{items}[0]{values}{species}{tax_id}, 3702, 'Search result species');
  is($content->{items}[1]{values}{assembly}{accession}, 'GCA_000754195.2', 'Search result assembly');

  # test the entries_per_page parameter
  $request = POST('/api/search?page=3&entries_per_page=2',
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of entries per page');
  is($content->{items}[0]{values}{hub}{shortLabel}, 'Plants', 'Search result hub');
  is($content->{items}[1]{values}{species}{scientific_name}, 'Homo sapiens', 'Search result species');
  
  # test with qeury string
  # blueprint hub has some metadata to look for
  $request = POST('/api/search',
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ query => 'monocyte male' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  is($content->{items}[0]{values}{hub}{shortLabel}, 'Blueprint Hub', 'Search result hub');
  is($content->{items}[0]{values}{assembly}{accession}, 'GCA_000001405.1', 'Search result assembly');

  $request = POST('/api/search?page=2',
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ query => 'neutrophil' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');
  
}

done_testing();
