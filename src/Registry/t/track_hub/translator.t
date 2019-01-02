# Copyright [2015-2019] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use JSON;
use List::Util qw(first);
use Registry::TrackHub;
use Registry::GenomeAssembly::Schema;
use Registry::Utils;

use_ok 'Registry::TrackHub::Translator';

my $version = 'v1.0';

throws_ok { Registry::TrackHub::Translator->new() } qr/Undefined/, "Throws if required args are undefined";

my $translator = Registry::TrackHub::Translator->new(version => $version, permissive => 1);
isa_ok($translator, 'Registry::TrackHub::Translator');
is($translator->version, $version, 'JSON version');

throws_ok { $translator->translate } qr/Undefined/, "Throws if translate have missing arguments";
throws_ok { Registry::TrackHub::Translator->new(version => '0.1')->translate } 
  qr/not supported/, "Throws when translate to unsupported version";

SKIP: {
  skip "No Internet connection: cannot test TrackHub translation on public Track Hubs", 9
    unless Registry::Utils::internet_connection_ok();

  my $WRONG_URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/xxx/trackDb.txt";
  throws_ok { $translator->translate($WRONG_URL, 'hg18') } qr/check the source/, "Throws if translate is given wrong URL";

  my ($URL, $json_docs);

  #
  # Test Bluprint Track Data Hub
  #
  note "Checking translation of Bluprint trackhub";
  $URL = "http://ftp.ebi.ac.uk/pub/databases/blueprint/releases/20150128/homo_sapiens/hub";
  throws_ok { $translator->translate($URL, 'hg18') } qr/No genome data/, "Throws if translate is given wrong assembly";

  $json_docs = $translator->translate($URL, 'hg19');
  is(scalar @{$json_docs}, 1, "Correct number of translations");

  open my $FH, '>',"$Bin/blueprint.json" or die "Cannot open blueprint.json: $!\n";
  print $FH $json_docs->[0];
  close $FH;

  my $doc = from_json($json_docs->[0]);
  is($doc->{version}, 'v1.0', 'Correct JSON version');
  ok($doc->{hub}, 'Hub property exists');
  like($doc->{hub}{name}, qr/Blueprint_Hub/, 'Correct Hub name');
  is($doc->{hub}{shortLabel}, 'Blueprint Hub', 'Correct Hub shortLabel');
  is($doc->{hub}{longLabel}, 'Blueprint Epigenomics Data Hub', 'Correct Hub longLabel');
  is($doc->{hub}{url}, $URL, 'Hub URL');
  is($doc->{source}{url}, Registry::TrackHub->new(url => $URL, permissive => 1)->get_genome('hg19')->trackDb->[0], "TrackDB source URL");
  
  is_deeply($doc->{species}, { tax_id => 9606, 
  			       scientific_name => 'Homo sapiens', 
  			       common_name => 'human' }, 'Correct species');
  is_deeply($doc->{assembly}, { name => 'GRCh37', 
  				long_name => 'Genome Reference Consortium Human Build 37 (GRCh37)',
  				accession => 'GCA_000001405.1', 
  				synonyms => 'hg19' }, 'Correct assembly');

  note "Checking container (bp) metadata";
  my $metadata = first { $_->{id} eq 'bp' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, 'Blueprint', 'Container name');
  
  note "Checking metadata of random track (bpHistoneModsC0010KH1H3K36me3MACS2_broad_peakEMBL-EBI)";
  $metadata = first { $_->{id} eq 'bpHistoneModsC0010KH1H3K36me3MACS2_broad_peakEMBL-EBI' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, "C0010K H3K36me3 MACS2_broad_peak CD14-positive, CD16-negative classical monocyte peak from NCMLS", 
     "Corrent name");
  is($metadata->{MOLECULE}, 'genomic_DNA', 'Correct MOLECULE metadata');
  like($metadata->{SAMPLE_ONTOLOGY_URI}, qr/UBERON_0013756/, 'Correct SAMPLE_ONTOLOGY_URI metadata');
  is($metadata->{CELL_TYPE}, 'CD14-positive,_CD16-negative_classical_monocyte', 'Correct CELL_TYPE metadata');

  note("Checking another random track (bpHistoneModsC00264H1H3K27me3MACS2_wigglerEMBL-EBIwiggler)");
  $metadata = first { $_->{id} eq 'bpHistoneModsC00264H1H3K27me3MACS2_wigglerEMBL-EBIwiggler' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, "C00264 H3K27me3 MACS2_wiggler CD14-positive, CD16-negative classical monocyte signal from NCMLS", 
     "Corrent name");
  is($metadata->{EPIRR_ID}, 'IHECRE00000135.1', 'Correct EPIRR_ID metadata');
  is($metadata->{BIOMATERIAL_TYPE}, 'Primary_Cell', 'Correct metadata');
  is($metadata->{SAMPLE_ID}, 'ERS158623', 'Correct SAMPLE_ID metadata');

  note "Checking display and configuration options";
  is(scalar keys $doc->{configuration}, 1, "One root object");
  is(scalar keys $doc->{configuration}{bp}{members}, 2, "Two views under container object");
  my $view = $doc->{configuration}{bp}{members}{region};
  ok($view, "View exists");
  is($view->{shortLabel}, 'Blueprint Region', "Correct view label");
  my $member = $view->{members}{'bpDNAMethC003K951BS-Seqhypo_methylationCNAG'};
  ok($member, "View member exists");
  is($member->{type}, "bigbed", "View member type");
  is($member->{color}, "252,180,100", "View member color");
  is($member->{subGroups}{analysis_group}, "CNAG", "View member subgroup");
  $view = $doc->{configuration}{bp}{members}{signal};
  is($view->{visibility}, 'pack', "Correct view visibility");
  $member = $view->{members}{'bpDNAMethC002CTA1bsBS-SeqCPG_methylation_sdCNAG'};
  ok($member, "View member exists");
  is($member->{type}, "bigwig", "View member type");
  is($member->{bigDataUrl}, 'http://ftp.ebi.ac.uk/pub/databases/blueprint/data/homo_sapiens/GRCh37/Venous_blood/C002CT/cytotoxic_CD56-dim_natural_killer_cell/Bisulfite-Seq/CNAG/C002CTA1bs.CPG_methylation_sd.bs_call.20140106.bw', "View member bigDataUrl");
  is($member->{shortLabel}, 'C002CT.BS-Seq.StDev.NK', "View member short label");
  
  #
  # Test other public Track Data Hubs
  #
  note "Checking translation of Plants trackhub";
  $URL = "http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants";
  $json_docs = $translator->translate($URL);
  is(scalar @{$json_docs}, 3, "Number of translated track dbs");

  my $i = 1;
  for my $doc (@{$json_docs}) {
    open $FH, ">$Bin/plant$i.json" or die "Cannot open plant$i.json: $!\n";
    print $FH $doc;
    close $FH;
    $i++;

    $doc = from_json($doc);
    is($doc->{version}, 'v1.0', 'Correct JSON version');
    ok($doc->{hub}, 'Hub property exists');
    is($doc->{hub}{name}, 'cshl2013', 'Correct Hub name');
    is($doc->{hub}{shortLabel}, 'Plants', 'Correct Hub shortLabel');
    is($doc->{hub}{longLabel}, 'CSHL Biology of Genomes meeting 2013 demonstration assembly hub', 'Correct Hub longLabel');
    is($doc->{hub}{url}, $URL, 'Hub URL');
    ok($doc->{species}{tax_id} == 3702 || $doc->{species}{tax_id} == 3988 || $doc->{species}{tax_id} == 3711, 
       "Expected species");
    if ($doc->{species}{tax_id} == 3702) {
      is($doc->{source}{url}, Registry::TrackHub->new(url => $URL, permissive => 1)->get_genome('araTha1')->trackDb->[0], "TrackDB source URL");
      is_deeply($doc->{species}, { tax_id => 3702, 
				   scientific_name => 'Arabidopsis thaliana', 
				   common_name => 'thale cress' }, 'Correct species');
      is_deeply($doc->{assembly}, { name => 'TAIR10', 
				    accession => 'GCA_000001735.1', 
				    synonyms => 'araTha1' }, 'Correct assembly');

      # check metadata and configuration
      is(scalar @{$doc->{data}}, 23, "Number of tracks");

      my $metadata = first { $_->{id} eq 'genscan_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'genscan_', 'Track id');
      is($metadata->{name}, 'Genscan Gene Predictions', 'Track name');

      $metadata = first { $_->{id} eq 'repeatMaskerRNA_' } @{$doc->{data}};
      ok($metadata, "Track metadata exists");
      is($metadata->{id}, 'repeatMaskerRNA_', 'Track id');
      is($metadata->{name}, 'RNA Repeating Elements by RepeatMasker', 'Track name');
      
      is(scalar keys $doc->{configuration}, 14, "Root configuration cardinality");
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
      is($doc->{source}{url}, Registry::TrackHub->new(url => $URL, permissive => 1)->get_genome('ricCom1')->trackDb->[0], "TrackDB source URL");
      is_deeply($doc->{species}, { tax_id => 3988, 
				   scientific_name => 'Ricinus communis', 
				   common_name => 'castor bean' }, 'Correct species');
      is_deeply($doc->{assembly}, { name => 'JCVI_RCG_1.1', 
				    accession => 'GCA_000151685.2', 
				    synonyms => 'ricCom1' }, 'Correct assembly');

      # check metadata and configuration
      is(scalar @{$doc->{data}}, 13, "Number of tracks");

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
      is($doc->{source}{url}, Registry::TrackHub->new(url => $URL, permissive => 1)->get_genome('braRap1')->trackDb->[0], "TrackDB source URL");
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

  note "Checking translation of DNA Methylation trackhub";
  $URL = "http://smithlab.usc.edu/trackdata/methylation";
  $json_docs = $translator->translate($URL, 'mm10');
  is(scalar @{$json_docs}, 1, "Number of translated track dbs");
  $doc = from_json($json_docs->[0]);
  ok($doc->{hub}, 'Hub property exists');
  is($doc->{hub}{name}, 'Smith Lab Public Hub', 'Correct Hub name');
  is($doc->{hub}{shortLabel}, 'DNA Methylation', 'Correct Hub shortLabel');
  is($doc->{hub}{longLabel}, 'Hundreds of analyzed methylomes from bisulfite sequencing data', 'Correct Hub longLabel');
  is($doc->{hub}{url}, $URL, 'Hub URL');
  is($doc->{source}{url}, Registry::TrackHub->new(url => $URL, permissive => 1)->get_genome('mm10')->trackDb->[0], "TrackDB source URL");

  open $FH, ">$Bin/meth.json" or die "Cannot open meth.json: $!\n";
  print $FH $json_docs->[0];
  close $FH;

  is_deeply($doc->{species}, { tax_id => 10090, 
			       scientific_name => 'Mus musculus', 
			       common_name => 'house mouse' }, 'Correct species');
  is_deeply($doc->{assembly}, { name => 'GRCm38',
				long_name => 'Genome Reference Consortium Mouse Build 38',
				accession => 'GCA_000001635.2', 
				synonyms => 'mm10' }, 'Correct assembly');

  # check metadata and configuration
  # is(scalar @{$doc->{data}}, 649, "Number of data tracks");

  $metadata = first { $_->{id} eq 'Liu_Mouse_2014' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{id}, 'Liu_Mouse_2014', 'Track id');
  is($metadata->{name}, 'Setdb1 is required for germline development and silencing of H3K9me3-marked endogenous retroviruses in primordial germ cells', 'Track name');
  my $conf = $doc->{configuration}{Liu_Mouse_2014};
  ok($conf, "Track configuration exists");
  is(scalar keys %{$conf->{members}}, 6, "Number of composite members");
  $member = $conf->{members}{AMRLiu_Mouse_2014};
  ok($member, "Child configuration exists");
  is($member->{shortLabel}, 'AMR', "Member shortLabel");
  is(scalar keys %{$member->{members}}, 2, "Number of view members");
  my $member_member = $member->{members}{LiuMouse2014_MouseE13MalePGCSetdb1KOAMR};
  ok($member_member, "View member exists");
  is($member_member->{type}, "bigbed", "View member type");
  is($member_member->{longLabel}, "Mouse_E13-Male-PGC-Setdb1-KO_AMR", "View member longLabel");
  is($member_member->{bigDataUrl}, "http://smithlab.usc.edu/methbase/data/Liu-Mouse-2014/Mouse_E13-Male-PGC-Setdb1-KO/tracks_mm10/Mouse_E13-Male-PGC-Setdb1-KO.amr.bb", "View member bigDataUrl");

  $metadata = first { $_->{id} eq 'Lister_Brain_2013' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{id}, 'Lister_Brain_2013', 'Track id');
  is($metadata->{name}, 'Global Epigenomic Reconfiguration During Mammalian Brain Development', 'Track name');
  $conf = $doc->{configuration}{Lister_Brain_2013};
  ok($conf, "Track configuration exists");
  is(scalar keys %{$conf->{members}}, 6, "Number of composite members");
  $member = $conf->{members}{ReadLister_Brain_2013};
  ok($member, "Child configuration exists");
  is($member->{shortLabel}, 'Read', "Member shortLabel");
  is(scalar keys %{$member->{members}}, 15, "Number of view members");
  $member_member = $member->{members}{ListerBrain2013_MouseFrontCortexNeuronMale7WkRead};
  ok($member_member, "View member exists");
  is($member_member->{type}, "bigwig", "View member type");
  is($member_member->{longLabel}, "Mouse_FrontCortexNeuronMale7Wk_Read", "View member longLabel");
  is($member_member->{bigDataUrl}, "http://smithlab.usc.edu/methbase/data/Lister-Brain-2013/Mouse_FrontCortexNeuronMale7Wk/tracks_mm10/Mouse_FrontCortexNeuronMale7Wk.read.bw", "View member bigDataUrl");

  note "Checking Roadmap Epigenomics Data VizHub";
  $URL = "http://vizhub.wustl.edu/VizHub/RoadmapReleaseAll.txt";
  $json_docs = $translator->translate($URL);
  is(scalar @{$json_docs}, 1, "Number of translated track dbs");

  open $FH, ">$Bin/vizhub.json" or die "Cannot open vizhub.json: $!\n";
  print $FH $json_docs->[0];
  close $FH;

  $doc = from_json($json_docs->[0]);
  ok($doc->{hub}, 'Hub property exists');
  is($doc->{hub}{name}, 'VizHub', 'Correct Hub name');
  is($doc->{hub}{shortLabel}, 'Roadmap Epigenomics Data Complete Collection at Wash U VizHub', 'Correct Hub shortLabel');
  is($doc->{hub}{longLabel}, 'Roadmap Epigenomics Human Epigenome Atlas Data Complete Collection, VizHub at Washington University in St. Louis', 'Correct Hub longLabel');
  is($doc->{hub}{url}, $URL, 'Hub URL');
  is($doc->{source}{url}, Registry::TrackHub->new(url => $URL, permissive => 1)->get_genome('hg19')->trackDb->[0], "TrackDB source URL");

  is_deeply($doc->{species}, { tax_id => 9606, 
  			       scientific_name => 'Homo sapiens', 
  			       common_name => 'human' }, 'Correct species');
  is_deeply($doc->{assembly}, { name => 'GRCh37', 
  				long_name => 'Genome Reference Consortium Human Build 37 (GRCh37)',
  				accession => 'GCA_000001405.1', 
  				synonyms => 'hg19' }, 'Correct assembly');

  $metadata = first { $_->{id} eq 'BBF_mRNA_71_72' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, "UCSF-UBC-USC Breast Fibroblast Primary Cells mRNA-Seq Donor RM071 Library A18472 EA Release 9", 
     "Corrent name");
  is($metadata->{sample_alias}, "Breast Fibroblast RM071, batch 1", 'Correct sample alias');
  is($metadata->{sample_common_name}, "Breast, Fibroblast Primary Cells", 'Correct sample common name');
  is($metadata->{experiment_type}, 'mRNA-Seq', 'Correct experiment type');
  is($metadata->{extraction_protocol}, "BCCAGSC mRNA Standard Operating Procedure", 'Correct extraction protocol metadata');
  is($metadata->{library_generation_pcr_number_cycles}, 10, 'Correct library generation PCR num cycles');

  $metadata = first { $_->{id} eq 'XBMC_H3K9me3_TC010A' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, "Peripheral_Blood_Mononuclear_Primary_Cells H3K9me3 Histone Modification by Chip-seq Signal from REMC/UCSF (Hotspot_Score=0.1958 Pcnt=66 DonorID:TC010)", 
     "Corrent name");
  is($metadata->{biomaterial_provider}, "Weiss Lab UCSF", 'Correct biomaterial provider metadata');
  is($metadata->{chip_protocol}, "Farnham Lab Protocol", 'Correct chip protocol metadata');
  is($metadata->{chip_antibody}, 'H3K9me3', 'Correct chip antibody metadata');

  $metadata = first { $_->{id} eq 'BFLL_mRNA_14_58' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, "UW Fetal Lung Left mRNA-Seq Donor H-23914 Library lib-RNA.RS18158 EA Release 9", 
     "Corrent name");
  is($metadata->{sample_common_name}, "Fetal Lung, Left", 'Correct sample common name metadata');
  is($metadata->{extraction_protocol}, "Qiagen TissueLyser and RNeasy Lipid Tx Mini kit", 'Correct extraction protocol metadata');

  $metadata = first { $_->{id} eq 'XBMC_H3K9me3_TC010A' } @{$doc->{data}};
  ok($metadata, "Track metadata exists");
  is($metadata->{name}, "Peripheral_Blood_Mononuclear_Primary_Cells H3K9me3 Histone Modification by Chip-seq Signal from REMC/UCSF (Hotspot_Score=0.1958 Pcnt=66 DonorID:TC010)", 
     "Corrent name");
  is($metadata->{biomaterial_provider}, "Weiss Lab UCSF", 'Correct biomaterial provider metadata');
  is($metadata->{chip_protocol}, "Farnham Lab Protocol", 'Correct chip protocol metadata');
  is($metadata->{chip_antibody}, 'H3K9me3', 'Correct chip antibody metadata');
  
}

done_testing();
