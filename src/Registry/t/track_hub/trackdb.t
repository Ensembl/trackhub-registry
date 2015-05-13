use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

local $SIG{__WARN__} = sub {};

use JSON;
use Registry::Utils;
use Registry::TrackHub::Translator;

use_ok 'Registry::TrackHub::TrackDB';

throws_ok { Registry::TrackHub::TrackDB->new() } qr/Undefined/, 'Throws if doc not passed';
throws_ok { Registry::TrackHub::TrackDB->new({ data => [] }) } qr/correct format/, 'Throws if doc with incorrect format passed (no configuration)';
throws_ok { Registry::TrackHub::TrackDB->new({ configuration => [] }) } qr/correct format/, 'Throws if doc with incorrect format passed (configuration not a hash)';

SKIP: {
  skip "No Internet connection: cannot test TrackHub access", 66
    unless Registry::Utils::internet_connection_ok();

  # tests with the example tracks from v1.0 schema
  my $doc = from_json(Registry::Utils::slurp_file("$Bin/../trackhub-examples/blueprint1.json"));
  my $trackdb = Registry::TrackHub::TrackDB->new($doc);
  isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
  my $info = $trackdb->track_info;
  is(scalar keys %{$info}, 1, 'Number of tracks');
  is($info->{bpDnaseRegionsC0010K46DNaseEBI}[0], 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Track URL');
  is($info->{bpDnaseRegionsC0010K46DNaseEBI}[1], 0, 'URL does not exist');
  is($info->{bpDnaseRegionsC0010K46DNaseEBI}[2], '404: Not Found', 'Error response');

  $doc = from_json(Registry::Utils::slurp_file("$Bin/../trackhub-examples/blueprint2.json"));
  $trackdb = Registry::TrackHub::TrackDB->new($doc);
  isa_ok($trackdb, 'Registry::TrackHub::TrackDB');

  $info = $trackdb->track_info;
  is(scalar keys %{$info}, 4, 'Number of tracks');
  foreach my $track (keys %{$info}) {
    note "Track $track";
    is($info->{$track}[1], 0, 'URL does not exist');
    is($info->{$track}[2], '599: Internal Exception', 'Error response'); # not valid URL (bad hostname generates internal exception)
  }

  # now test some public hubs
  my $translator = Registry::TrackHub::Translator->new(version => 'v1.0');
  note "Checking Plants trackhub";
  my $URL = "http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants";
  my $json_docs = $translator->translate($URL);
  is(scalar @{$json_docs}, 3, "Number of translated track dbs");
  for my $doc (@{$json_docs}) {
    $doc = from_json($doc);
    $trackdb = Registry::TrackHub::TrackDB->new($doc);
    isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
    $info = $trackdb->track_info;
    if ($doc->{species}{tax_id} == 3702) { # Arabidopsis thaliana
      is(scalar keys %{$info}, 20, 'Number of tracks');
    } elsif ($doc->{species}{tax_id} == 3988) { # Ricinus communis
      is(scalar keys %{$info}, 12, 'Number of tracks');
    } else { # Brassica rapa
      is(scalar keys %{$info}, 12, 'Number of tracks');
    }
    # all tracks should work
    map { ok($info->{$_}[1], 'Bigdata file exists') } keys %{$info};
  }
  
}

done_testing();
