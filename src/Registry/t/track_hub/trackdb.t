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
  # use Data::Dumper; print Dumper($doc);
  my $trackdb = Registry::TrackHub::TrackDB->new($doc);
  isa_ok($trackdb, 'Registry::TrackHub::TrackDB');

}

done_testing();
