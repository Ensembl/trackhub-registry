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
    84 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();

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
  my @public_hubs = (
		     { name => 'polyA', url => 'http://johnlab.org/xpad/Hub/UCSC.txt' },
		     { name => 'mRNA', url => 'http://www.mircode.org/ucscHub/hub.txt' },
		     { name => 'blueprint', url => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub' },
		     { name => 'plants', url => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt' },
		     { name => 'ensembl', url => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt' },
		     { name => 'rnaseq', url => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt' },
		     { name => 'zebrafish', url => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt' },
		     { name => 'sanger', url => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt' },
		     { name => 'thornton', url => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt' },
		    );

  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  foreach my $hub (@public_hubs) {
    note sprintf "Submitting hub %s", $hub->{name};
    $request = POST('/api/trackhub/create',
		    'Content-type' => 'application/json',
		    'Content'      => to_json({ url => $hub->{url} }));
    $request->headers->header(user       => 'trackhub1');
    $request->headers->header(auth_token => $auth_token);
    ok($response = request($request), 'POST request to /api/trackhub/create');
    ok($response->is_success, 'Request successful 2xx');
    is($response->content_type, 'application/json', 'JSON content type');
  }

  #
  # /api/search endpoint
  #
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
  is($content->{items}[1]{values}{hub}{longLabel}, 'Evidence summaries and provisional results for the new Ensembl Regulatory Build', 'Search result hub');
  is($content->{items}[3]{values}{assembly}{name}, 'MGSCv37', 'Search result assembly');

  # test getting the n-th page
  $request = POST('/api/search?page=3',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{items}[0]{values}{species}{tax_id}, 3988, 'Search result species');
  is($content->{items}[1]{values}{assembly}{accession}, 'GCA_000001405.1', 'Search result assembly');

  # test the entries_per_page parameter
  $request = POST('/api/search?page=3&entries_per_page=2',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ query => '' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 2, 'Number of entries per page');
  is($content->{items}[0]{values}{hub}{shortLabel}, 'miRcode microRNA sites', 'Search result hub');
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
  
  # test with some filters
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ species => 'Danio rerio'}));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 3, 'Number of search results');
  is($content->{items}[0]{values}{species}{tax_id}, '7955', 'Search result species');
  is($content->{items}[0]{values}{hub}{shortLabel}, 'ZebrafishGenomics', 'Search result hub');
  is($content->{items}[1]{values}{assembly}{name}, 'GRCz10', 'Search result assembly');

  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ species  => 'Danio rerio',
					      assembly => 'GRCz10' }));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 1, 'Number of search results');
  is($content->{items}[0]{values}{hub}{shortLabel}, 'GRC Genome Issues under Review', 'Search result hub');
  
  # incompatible filters should return no results
  $request = POST('/api/search',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ species  => 'Danio rerio',
					      assembly => 'GRCh37'}));
  ok($response = request($request), 'POST request to /api/search');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is(scalar @{$content->{items}}, 0, 'Number of search results');
  
  #
  # /api/search/trackdb/:id endpoint
  #
  # non GET request should fail
  $request = POST('/api/search/trackdb/1');
  ok($response = request($request), 'POST request to /api/search/trackdb/:id');
  is($response->code, 405, 'Request unsuccessful 405');

  $request = GET('/api/search/trackdb/2');
  ok($response = request($request), 'GET request to /api/search/trackdb/:id');
  ok($response->is_success, 'Request successful');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  is($content->{hub}{name}, 'miRcodeHub', 'TrackDB hub name');
  is($content->{configuration}{mir_sites_highcons}{bigDataUrl}, 'http://www.mircode.org/ucscHub/hg19/gencode_mirsites_highconsfamilies.bb', 'TrackDB configuration');
  # shouldn't have the metadata
  ok(!$content->{data}, 'No metadata');
  
}

done_testing();
