use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use Registry::TrackHub;
use Registry::Utils;

use_ok 'Registry::TrackHub::Parser';

throws_ok { Registry::TrackHub::Parser->new() } qr/Undefined/, 'Throws if files are not passed';


SKIP: {
  skip "No Internet connection: cannot test Track DB parsing", 8
    unless Registry::Utils::internet_connection_ok();

  my $WRONG_LOCATION = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/xxx/trackDb.txt";
  my $parser = Registry::TrackHub::Parser->new(files => [ $WRONG_LOCATION ]);
  throws_ok { $parser->parse } qr/xxx/, 'Throws if cannot read trackdb files';

  my $URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub";
  my $th = Registry::TrackHub->new(url => $URL);
  $parser = Registry::TrackHub::Parser->new(files => $th->trackdb_conf_for_assembly('hg19'));
  isa_ok($parser, 'Registry::TrackHub::Parser');

  
}

done_testing();
