use strict;
use warnings;
use Test::More;

use JSON;
use List::Util qw( first );
use HTTP::Request::Common qw/GET POST/;
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use Catalyst::Test 'Registry';

use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

my $request = GET('/api/info/version');
ok(my $response = request($request), 'GET request to /api/info/version');
ok($response->is_success, 'Request successful');
my $content = from_json($response->content);
is($content->{release}, $Registry::VERSION, "API current version is $Registry::VERSION");

SKIP: {
  skip "Cannot run tests: either elasticsearch is not running or there's no internet connection",
    62 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();
  
  # /api/info/ping
  my $request = GET('/api/info/ping');
  ok(my $response = request($request), 'GET request to /api/info/ping');
  ok($response->is_success, 'Request successful');
  my $content = from_json($response->content);
  ok($content->{ping}, 'Service available');

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

  $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok($response = request($request), 'Request to log in');
  $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  foreach my $hub (@public_hubs) {
    note sprintf "Submitting hub %s", $hub->{name};
    $request = POST('/api/trackhub?permissive=1',
		    'Content-type' => 'application/json',
		    'Content'      => to_json({ url => $hub->{url} }));
    $request->headers->header(user       => 'trackhub1');
    $request->headers->header(auth_token => $auth_token);
    ok($response = request($request), 'POST request to /api/trackhub/create');
    ok($response->is_success, 'Request successful 2xx');
    is($response->content_type, 'application/json', 'JSON content type');
  }

  #
  # /api/info/species endpoint
  #
  my %species_assemblies = 
    ( 'Homo sapiens'         => ['GCA_000001405.1', 'GCA_000001405.15'],
      'Danio rerio'          => ['GCA_000002035.2', 'GCA_000002035.3'],
      'Mus musculus'         => ['GCA_000001635.1', 'GCA_000001635.2'], 
      'Arabidopsis thaliana' => ['GCA_000001735.1'],
      'Brassica rapa'        => ['GCA_000309985.1'],
      'Drosophila simulans'  => ['GCA_000754195.2'], 
      'Ricinus communis'     => ['GCA_000151685.2']);

  $request = GET('/api/info/species');
  ok($response = request($request), 'GET request to /api/info/species');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is_deeply([ sort @{$content} ], [ sort keys %species_assemblies ], 'List of species');

  #
  # /api/info/asseblies endpoint
  #
  $request = GET('/api/info/assemblies');
  ok($response = request($request), 'GET request to /api/info/assemblies');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is_deeply([ sort keys %{$content} ], [ sort keys %species_assemblies ], 'List of species');
  foreach my $species (keys %{$content}) {
    is_deeply($content->{$species}, $species_assemblies{$species}, "Assemblies for species $species");
  }

  #
  # /api/info/trackhubs
  #
  $request = GET('/api/info/trackhubs');
  ok($response = request($request), 'GET request to /api/info/trackhubs');
  ok($response->is_success, 'Request successful');
  $content = from_json($response->content);
  is(scalar @{$content}, 9, 'Number of hubs');

  # test a couple of hubs
  my $hub = first { $_->{name} eq 'EnsemblRegulatoryBuild' } @{$content};
  ok($hub, 'Ensembl regulatory build hub');
  is($hub->{longLabel}, 'Evidence summaries and provisional results for the new Ensembl Regulatory Build', 'Hub longLabel');
  is(scalar @{$hub->{trackdbs}}, 2, 'Number of trackDbs');
  is($hub->{trackdbs}[0]{species} && $hub->{trackdbs}[1]{species}, 9606, 'trackDb species');
  like($hub->{trackdbs}[0]{assembly}, qr/GCA_000001405/, 'trackDb assembly');
  like($hub->{trackdbs}[1]{assembly}, qr/GCA_000001405/, 'trackDb assembly');
  like($hub->{trackdbs}[0]{uri}, qr/api\/trackdb/, 'trackDb uri');
  like($hub->{trackdbs}[1]{uri}, qr/api\/trackdb/, 'trackDb uri');

  $hub = first { $_->{name} eq 'NHGRI-1' } @{$content};
  ok($hub, 'Zebrafish hub');
  is($hub->{shortLabel}, 'ZebrafishGenomics', 'Hub shortLabel');
  is(scalar @{$hub->{trackdbs}}, 1, 'Number of trackDbs');
  is($hub->{trackdbs}[0]{species}, 7955, 'trackDb species');
  is($hub->{trackdbs}[0]{assembly}, 'GCA_000002035.2', 'trackDb assembly');
  like($hub->{trackdbs}[0]{uri}, qr/api\/trackdb/, 'trackDb uri');

}

done_testing();