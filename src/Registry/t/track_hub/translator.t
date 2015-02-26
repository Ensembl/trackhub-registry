use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use JSON;
use Registry::GenomeAssembly::Schema;
use Registry::Utils;

use_ok 'Registry::TrackHub::Translator';

my $version = '1.0';

throws_ok { Registry::TrackHub::Translator->new() } qr/Undefined/, "Throws if required args are both undefined";
throws_ok { Registry::TrackHub::Translator->new(version => $version) } qr/Undefined/, "Throws if one required args is undefined";

my $gcschema = 
  Registry::GenomeAssembly::Schema->connect("DBI:Oracle:host=ora-vm5-003.ebi.ac.uk;sid=ETAPRO;port=1571", 
					    'gc_reader', 
					    'reader', 
					    { 'RaiseError' => 1, 'PrintError' => 0 });
my $gc_assembly_set = $gcschema->resultset('GCAssemblySet');

my $translator = Registry::TrackHub::Translator->new(version => $version, 
						     gc_assembly_set => $gc_assembly_set);
isa_ok($translator, 'Registry::TrackHub::Translator');
is($translator->version, $version, 'JSON version');

throws_ok { Registry::TrackHub::Translator->new(version => '0.1', 
						gc_assembly_set => $gc_assembly_set)->translate } 
  qr/not supported/, "Throws when translate to unsupported version";


SKIP: {
  skip "No Internet connection: cannot test TrackHub translation", 8
    unless Registry::Utils::internet_connection_ok();

  $translator = Registry::TrackHub::Translator->new(version => $version,
						    gc_assembly_set => $gc_assembly_set);
  isa_ok($translator, 'Registry::TrackHub::Translator');
  throws_ok { $translator->translate } qr/Undefined/, "Throws if translate have missing arguments";

  my $WRONG_URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/xxx/trackDb.txt";
  my $URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub";
  throws_ok { $translator->translate($WRONG_URL, 'hg18') } qr/check the source/, "Throws if translate is given wrong URL";
  throws_ok { $translator->translate($URL, 'hg18') } qr/No genome data/, "Throws if translate is given wrong assembly";

  my $json_docs = $translator->translate($URL, 'hg19');
  is(scalar @{$json_docs}, 1, "Correct number of translations");

  my $doc = from_json($json_docs->[0]);
  is($doc->{version}, '1.0', 'Correct JSON version');
  is($doc->{hub}, 'Blueprint Epigenomics Data Hub', 'Correct Hub');
  is_deeply($doc->{species}, { tax_id => 9606, 
			       scientific_name => 'Homo sapiens', 
			       common_name => 'human' }, 'Correct species');
  is_deeply($doc->{assembly}, { name => 'GRCh37', 
				long_name => 'Genome Reference Consortium Human Build 37 (GRCh37)',
				accession => 'GCA_000001405.1', 
				synonyms => 'hg19' }, 'Correct assembly');

}

done_testing();
