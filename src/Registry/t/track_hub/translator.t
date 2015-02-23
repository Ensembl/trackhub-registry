use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use Registry::Utils;

use_ok 'Registry::TrackHub::Translator';

throws_ok { Registry::TrackHub::Translator->new() } qr/Undefined/, "Throws if version undefined";

my $version = '1.0';
my $translator = Registry::TrackHub::Translator->new(version => $version);
isa_ok($translator, 'Registry::TrackHub::Translator');
is($translator->version, $version, 'JSON version');

throws_ok { Registry::TrackHub::Translator->new(version => '0.1')->translate } 
  qr/not supported/, "Throws when translate to unsupported version";


SKIP: {
  skip "No Internet connection: cannot test TrackHub translation", 8
    unless Registry::Utils::internet_connection_ok();

  $translator = Registry::TrackHub::Translator->new(version => $version);
  isa_ok($translator, 'Registry::TrackHub::Translator');
  throws_ok { $translator->translate } qr/Undefined/, "Throws if translate have missing arguments";
  my $WRONG_URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/xxx/trackDb.txt";
  my $URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub";
  throws_ok { $translator->translate($WRONG_URL, 'hg18') } qr/check the source/, "Throws if translate is given wrong URL";
  throws_ok { $translator->translate($URL, 'hg18') } qr/No genome data/, "Throws if translate is given wrong assembly";

  my $json_docs = $translator->translate($URL, 'hg19');

#   like($th->hub, qr/Blueprint_Hub/, 'Hub name');
#   is($th->shortLabel, 'Blueprint Hub', 'Hub short label');
#   is($th->longLabel, 'Blueprint Epigenomics Data Hub', 'Hub long label');
#   is($th->genomesFile, 'genomes.txt', 'Hub genomes file');
#   is($th->email, "blueprint-info\@ebi.ac.uk", 'Hub contact email');
#   like($th->descriptionUrl, qr/http:\/\/www.blueprint-epigenome.eu\/index.cfm/, 'Hub description URL');

#   is(scalar $th->assemblies, 1, 'Number of assemblies');
#   is(($th->assemblies)[0], 'hg19', 'Stored assembly');
#   is_deeply($th->genomes, { hg19 => [ "$URL/hg19/tracksDb.txt" ] }, 'Hub trackDb assembly info');
#   throws_ok { $th->trackdb_conf_for_assembly } qr/Undefined/, 'Throws if assembly not defined';
#   is_deeply($th->trackdb_conf_for_assembly('hg19'), [ "$URL/hg19/tracksDb.txt" ], 'TrackDB conf for assembly');
}

done_testing();
