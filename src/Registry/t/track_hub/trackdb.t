use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

local $SIG{__WARN__} = sub {};

use POSIX qw(strftime);
use JSON;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST/;
use Catalyst::Test 'Registry';

use Registry::Utils;
use Registry::Indexer;
use Registry::TrackHub::Translator;

use_ok 'Registry::TrackHub::TrackDB';

throws_ok { Registry::TrackHub::TrackDB->new() } qr/Undefined/, 'Throws if id not passed';

# tests with the example tracks from v1.0 schema
my $config = Registry->config()->{'Model::Search'};
my $indexer = Registry::Indexer->new(dir   => "$Bin/../trackhub-examples/",
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
$indexer->index_trackhubs();
$indexer->index_users();

my $id = 1;
my $trackdb = Registry::TrackHub::TrackDB->new($id);
isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
$trackdb->update_status();
my $status = $trackdb->status();
is($status->{tracks}{total}, 1, 'Number of tracks');
is($status->{tracks}{with_data}{total}, 1, 'Number of tracks with data');
is($status->{tracks}{with_data}{total_ko}, 1, 'Number of tracks with remote data unavailable');
is($status->{tracks}{with_data}{ko}{bpDnaseRegionsC0010K46DNaseEBI}[0], 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Track URL');
is($status->{tracks}{with_data}{ko}{bpDnaseRegionsC0010K46DNaseEBI}[1], '404: Not Found', 'Error response');
is($status->{message}, 'Remote Data Unavailable', 'Status message');
ok($status->{last_update}, 'Last update');
is_deeply($trackdb->file_type, [ 'bigBed' ], 'File type(s)');
note sprintf "Doc [%d] updated: %s", $id, $trackdb->status_last_update(1);

$id = 2;
$trackdb = Registry::TrackHub::TrackDB->new($id);
isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
$trackdb->update_status();
$status = $trackdb->status();
is($status->{tracks}{total}, 7, 'Number of tracks');
is($status->{tracks}{with_data}{total}, 4, 'Number of tracks with data');
is($status->{tracks}{with_data}{total_ko}, 4, 'Number of tracks with remote data unavailable');
foreach my $track (keys %{$status->{tracks}{with_data}{ko}}) {
  note "Track $track";
  is($status->{tracks}{with_data}{ko}{$track}[1], '599: Internal Exception', 'Error response'); # not valid URL (bad hostname generates internal exception)
}
is($status->{message}, 'Remote Data Unavailable', 'Status message');
ok($status->{last_update}, 'Last update');
is_deeply($trackdb->file_type, [ 'bigBed', 'bigWig' ], 'File type(s)');
note sprintf "Doc [%d] updated: %s", $id, $trackdb->status_last_update(1);

SKIP: {
  skip "No Internet connection or ES running cannot test TrackHub access", 25
    unless Registry::Utils::internet_connection_ok() and Registry::Utils::es_running();

  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  note "Checking Plants trackhub";
  my $URL = "http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants";  
  $request = POST('/api/trackhub/create?version=v1.0',
  		  'Content-type' => 'application/json',
  		  'Content'      => to_json({ url => $URL }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub/create');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  ok($content, "Docs created");
  is(scalar @{$content}, 3, "Correct number of trackdb docs created");
  my $location_header = $response->headers->{location};

  for my $doc (@{$content}) {
    my $location = shift @{$location_header};
    my ($id) = $location =~ /(\d+)$/;
    $trackdb = Registry::TrackHub::TrackDB->new($id);
    isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
    $status = $trackdb->update_status();
    if ($doc->{species}{tax_id} == 3702) { # Arabidopsis thaliana
      is($status->{tracks}{total}, 21, 'Number of tracks');
      is($status->{tracks}{with_data}{total}, 20, 'Number of tracks with data');
      is($status->{tracks}{with_data}{total_ko}, 0, 'Number of tracks with remote data unavailable');
      is($trackdb->compute_checksum, 'c70af2c480087b45848d60c9ae76f1ad', 'araTha1 checksum');
    } elsif ($doc->{species}{tax_id} == 3988) { # Ricinus communis
      is($status->{tracks}{total}, 13, 'Number of tracks');
      is($status->{tracks}{with_data}{total}, 12, 'Number of tracks with data');
      is($status->{tracks}{with_data}{total_ko}, 0, 'Number of tracks with remote data unavailable');
      is($trackdb->compute_checksum, 'f9561ae6f7883add3698fad7abab7e13', 'ricCom1 checksum');
    } else { # Brassica rapa
      is($status->{tracks}{total}, 13, 'Number of tracks');
      is($status->{tracks}{with_data}{total}, 12, 'Number of tracks with data');
      is($status->{tracks}{with_data}{total_ko}, 0, 'Number of tracks with remote data unavailable');
      is($trackdb->compute_checksum, '792d88bccacc240959e357409ccc2069', 'braRap1 checksum');
    }
    is($status->{message}, 'All is Well', 'Status message');
  }
  
}

done_testing();
