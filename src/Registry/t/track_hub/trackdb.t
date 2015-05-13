use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use JSON;
use Registry::Utils;

use_ok 'Registry::TrackHub::TrackDB';

throws_ok { Registry::TrackHub::TrackDB->new() } qr/Undefined/, 'Throws if doc not passed';
throws_ok { Registry::TrackHub::TrackDB->new({ data => [] }) } qr/correct format/, 'Throws if doc with incorrect format passed (no configuration)';
throws_ok { Registry::TrackHub::TrackDB->new({ configuration => [] }) } qr/correct format/, 'Throws if doc with incorrect format passed (configuration not a hash)';

SKIP: {
  skip "No Internet connection: cannot test TrackHub access", 1
    unless Registry::Utils::internet_connection_ok();

  # tests with the example tracks from v1.0 schema
  my $doc = from_json(Registry::Utils::slurp_file("$Bin/../trackhub-examples/blueprint1.json"));
  my $trackdb = Registry::TrackHub::TrackDB->new($doc);
  isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
  my $info = $trackdb->track_info;
  is(scalar keys %{$info}, 1, 'Number of tracks');
  is($info->{bpDnaseRegionsC0010K46DNaseEBI}[0], 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/Peripheral_blood/C0010K/Monocytes/DNase-Hypersensitivity//C0010K46.DNase.hotspot_v3_20130415.bb', 'Track URL');
  is($info->{bpDnaseRegionsC0010K46DNaseEBI}[1], 0, 'URL does not exit');
  is($info->{bpDnaseRegionsC0010K46DNaseEBI}[2], '404: Not Found', 'Error response');

}

done_testing();
