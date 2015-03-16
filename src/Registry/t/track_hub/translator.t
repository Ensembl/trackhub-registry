use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use JSON;
use List::Util qw(first);
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
  skip "No Internet connection: cannot test TrackHub translation on public Track Hubs", 9
    unless Registry::Utils::internet_connection_ok();

  $translator = Registry::TrackHub::Translator->new(version => $version,
						    gc_assembly_set => $gc_assembly_set);
  isa_ok($translator, 'Registry::TrackHub::Translator');
  throws_ok { $translator->translate } qr/Undefined/, "Throws if translate have missing arguments";

  my $WRONG_URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/xxx/trackDb.txt";
  throws_ok { $translator->translate($WRONG_URL, 'hg18') } qr/check the source/, "Throws if translate is given wrong URL";

  my ($URL, $json_docs);
  # note "Checking translation of Bluprint trackhub";
  # $URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub";
  # throws_ok { $translator->translate($URL, 'hg18') } qr/No genome data/, "Throws if translate is given wrong assembly";

  # $json_docs = $translator->translate($URL, 'hg19');
  # is(scalar @{$json_docs}, 1, "Correct number of translations");

  # my $doc = from_json($json_docs->[0]);
  # is($doc->{version}, '1.0', 'Correct JSON version');
  # is($doc->{hub}, 'Blueprint Epigenomics Data Hub', 'Correct Hub');
  # is_deeply($doc->{species}, { tax_id => 9606, 
  # 			       scientific_name => 'Homo sapiens', 
  # 			       common_name => 'human' }, 'Correct species');
  # is_deeply($doc->{assembly}, { name => 'GRCh37', 
  # 				long_name => 'Genome Reference Consortium Human Build 37 (GRCh37)',
  # 				accession => 'GCA_000001405.1', 
  # 				synonyms => 'hg19' }, 'Correct assembly');

  # note "Checking container (bp) metadata";
  # my $metadata = first { $_->{id} eq 'bp' } @{$doc->{data}};
  # ok($metadata, "Track metadata exists");
  # is($metadata->{name}, 'Blueprint', 'Container name');
  
  # note "Checking metadata of random track (bpHistoneModsC0010KH1H3K36me3MACS2_broad_peakEMBL-EBI)";
  # $metadata = first { $_->{id} eq 'bpHistoneModsC0010KH1H3K36me3MACS2_broad_peakEMBL-EBI' } @{$doc->{data}};
  # ok($metadata, "Track metadata exists");
  # is($metadata->{name}, "C0010K H3K36me3 MACS2_broad_peak CD14-positive, CD16-negative classical monocyte peak from NCMLS", 
  #    "Corrent name");
  # is($metadata->{MOLECULE}, 'genomic_DNA', 'Correct MOLECULE metadata');
  # like($metadata->{SAMPLE_ONTOLOGY_URI}, qr/UBERON_0013756/, 'Correct SAMPLE_ONTOLOGY_URI metadata');
  # is($metadata->{CELL_TYPE}, 'CD14-positive,_CD16-negative_classical_monocyte', 'Correct CELL_TYPE metadata');

  # note("Checking another random track (bpHistoneModsC00264H1H3K27me3MACS2_wigglerEMBL-EBIwiggler)");
  # $metadata = first { $_->{id} eq 'bpHistoneModsC00264H1H3K27me3MACS2_wigglerEMBL-EBIwiggler' } @{$doc->{data}};
  # ok($metadata, "Track metadata exists");
  # is($metadata->{name}, "C00264 H3K27me3 MACS2_wiggler CD14-positive, CD16-negative classical monocyte signal from NCMLS", 
  #    "Corrent name");
  # is($metadata->{EPIRR_ID}, 'IHECRE00000135.1', 'Correct EPIRR_ID metadata');
  # is($metadata->{BIOMATERIAL_TYPE}, 'Primary_Cell', 'Correct metadata');
  # is($metadata->{SAMPLE_ID}, 'ERS158623', 'Correct SAMPLE_ID metadata');

  # note "Checking display and configuration options";
  # is(scalar keys $doc->{configuration}, 1, "One root object");
  # is(scalar keys $doc->{configuration}{bp}{members}, 2, "Two views under container object");

  
  #
  # TODO
  # - test other public hubs
  #
  note "Checking translation of Plants trackhub";
  $URL = "http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants";
  $json_docs = $translator->translate($URL);
  is(scalar @{$json_docs}, 3, "Number of translated track dbs");
  for my $doc (@{$json_docs}) {
    $doc = from_json($doc);
    is($doc->{version}, '1.0', 'Correct JSON version');
    is($doc->{hub}, 'CSHL Biology of Genomes meeting 2013 demonstration assembly hub', 'Correct Hub');
    ok($doc->{species}{tax_id} == 3702 || $doc->{species}{tax_id} == 3988 || $doc->{species}{tax_id} == 3711, 
       "Expected species");
    if ($doc->{species}{tax_id} == 3702) {
      is_deeply($doc->{species}, { tax_id => 3702, 
				   scientific_name => 'Arabidopsis thaliana', 
				   common_name => 'thale cress' }, 'Correct species');
      is_deeply($doc->{assembly}, { name => 'TAIR10', 
				    accession => 'GCA_000001735.1', 
				    synonyms => 'araTha1' }, 'Correct assembly');

      # check metadata and configuration
      is(scalar @{$doc->{data}}, 21, "Number of data tracks");

      my $metadata = first { $_->{id} eq 'genscan_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'genscan_', 'Track id');
      is($metadata->{name}, 'Genscan Gene Predictions', 'Track name');

      $metadata = first { $_->{id} eq 'repeatMaskerRNA_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'repeatMaskerRNA_', 'Track id');
      is($metadata->{name}, 'RNA Repeating Elements by RepeatMasker', 'Track name');
      
      is(scalar keys $doc->{configuration}, 12, "Root configuration cardinality");
      my $conf = $doc->{configuration}{lastzBraRap1};
      ok($conf, "Configuration object exists");
      is($conf->{visibility}, 'dense', "Visibility attribute");
      is($conf->{bigDataUrl}, 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/araTha1/bbi/lastzAraTha1ToBraRap1.bb', "bigDataUrl attribute");

      $conf = $doc->{configuration}{repeatMasker_};
      ok($conf, "Configuration object exists");
      is($conf->{compositeTrack}, 'on', "Composite track");
      is($conf->{longLabel}, 'Repeating Elements by RepeatMasker', "longLabel attribute");
      is(scalar keys %{$conf->{members}}, 9, "Number of composite members");
      my $member = $conf->{members}{repeatMaskerSimple_};
      is($member->{longLabel}, 'Simple Repeating Elements by RepeatMasker', 'Member longLable attr');
      is($member->{bigDataUrl}, 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/araTha1/bbi/araTha1.rmsk.Simple.bb', 'Member bigDataUrl');

    } elsif ($doc->{species}{tax_id} == 3988) {
      is_deeply($doc->{species}, { tax_id => 3988, 
				   scientific_name => 'Ricinus communis', 
				   common_name => 'castor bean' }, 'Correct species');
      is_deeply($doc->{assembly}, { name => 'JCVI_RCG_1.1', 
				    accession => 'GCA_000151685.2', 
				    synonyms => 'ricCom1' }, 'Correct assembly');

      # check metadata and configuration
      is(scalar @{$doc->{data}}, 13, "Number of data tracks");

      my $metadata = first { $_->{id} eq 'gc5Base_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'gc5Base_', 'Track id');
      is($metadata->{name}, 'GC Percent in 5-Base Windows', 'Track name');

      $metadata = first { $_->{id} eq 'repeatMaskerLowComplexity_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'repeatMaskerLowComplexity_', 'Track id');
      is($metadata->{name}, 'Low Complexity Repeating Elements by RepeatMasker', 'Track name');
      
      is(scalar keys $doc->{configuration}, 9, "Root configuration cardinality");
      my $conf = $doc->{configuration}{simpleRepeat_};
      ok($conf, "Configuration object exists");
      is($conf->{priority}, 149.3, "Priority attribute");
      is($conf->{bigDataUrl}, 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/ricCom1/bbi/ricCom1.simpleRepeat.bb', "bigDataUrl attribute");

      $conf = $doc->{configuration}{repeatMasker_};
      ok($conf, "Configuration object exists");
      is($conf->{compositeTrack}, 'on', "Composite track");
      is($conf->{longLabel}, 'Repeating Elements by RepeatMasker', "longLabel attribute");
      is(scalar keys %{$conf->{members}}, 4, "Number of composite members");
      my $member = $conf->{members}{repeatMaskerRNA_};
      is($member->{maxWindowToDraw}, 10000000, 'Member maxWindowToDraw attr');
      is($member->{bigDataUrl}, 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/ricCom1/bbi/ricCom1.rmsk.RNA.bb', 'Member bigDataUrl');

    } else {
      is_deeply($doc->{species}, { tax_id => 3711, 
				   scientific_name => 'Brassica rapa', 
				   common_name => 'field mustard' }, 'Correct species');
      is_deeply($doc->{assembly}, { name => 'Brapa_1.0', 
				    accession => 'GCA_000309985.1', 
				    synonyms => 'braRap1' }, 'Correct assembly');

      is(scalar @{$doc->{data}}, 13, "Number of data tracks");

      my $metadata = first { $_->{id} eq 'windowMasker' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'windowMasker', 'Track id');
      is($metadata->{name}, 'Genomic Intervals Masked by WindowMasker + SDust', 'Track name');

      $metadata = first { $_->{id} eq 'repeatMaskerLTR_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'repeatMaskerLTR_', 'Track id');
      is($metadata->{name}, 'LTR Repeating Elements by RepeatMasker', 'Track name');
      
      is(scalar keys $doc->{configuration}, 8, "Root configuration cardinality");
      my $conf = $doc->{configuration}{gc5Base_};
      ok($conf, "Configuration object exists");
      is($conf->{type}, 'bigwig', "Type attribute");
      is($conf->{bigDataUrl}, 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/braRap1/bbi/braRap1.gc5Base.bw', "bigDataUrl attribute");

      $conf = $doc->{configuration}{repeatMasker_};
      ok($conf, "Configuration object exists");
      is($conf->{compositeTrack}, 'on', "Composite track");
      is($conf->{longLabel}, 'Repeating Elements by RepeatMasker', "longLabel attribute");
      is(scalar keys %{$conf->{members}}, 5, "Number of composite members");
      my $member = $conf->{members}{repeatMaskerLTR_};
      is($member->{type}, 'bigbed', 'Member type attr');
      is($member->{bigDataUrl}, 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/braRap1/bbi/braRap1.rmsk.LTR.bb', 'Member bigDataUrl');
      
    }
  }
}

done_testing();
