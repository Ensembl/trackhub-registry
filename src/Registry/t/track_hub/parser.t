# Copyright [2015-2016] EMBL-European Bioinformatics Institute
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
use Test::Deep;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use Registry::TrackHub;
use Registry::Utils;

use_ok 'Registry::TrackHub::Parser';

throws_ok { Registry::TrackHub::Parser->new() } qr/Undefined/, 'Throws if mandatory argument not passed';


SKIP: {
  skip "No Internet connection: cannot test Track DB parsing", 8
    unless Registry::Utils::internet_connection_ok();

  my $WRONG_LOCATION = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/xxx/trackDb.txt";
  my $parser = Registry::TrackHub::Parser->new(files => [ $WRONG_LOCATION ]);
  throws_ok { $parser->parse } qr/xxx/, 'Throws if cannot read trackdb files';

  my $URL = "http://ftp.ebi.ac.uk/pub/databases/blueprint/releases/20150128/homo_sapiens/hub";
  my $th = Registry::TrackHub->new(url => $URL, permissive => 1);
  $parser = Registry::TrackHub::Parser->new(files => $th->get_genome('hg19')->trackDb);
  isa_ok($parser, 'Registry::TrackHub::Parser');

  # now parse the tracksDB file
  my $tracks = $parser->parse;
  is(scalar keys %{$tracks}, 1445, 'Number of tracks');

  #
  # check data for a number of tracks
  #
  note("Checking composite higher level track (bp)");
  my $track = $tracks->{bp};
  ok($track, 'Track data exists');
  is($track->{shortLabel}, 'Blueprint', 'Correct shortLabel');
  is($track->{longLabel}, 'Blueprint', 'Correct longLabel');
  is($track->{type}, 'bed', 'Correct type');
  is($track->{compositeTrack}, 'on', 'Is composite track');
  is($track->{dimensions}{x}, 'experiment', 'Dimension X');
  is($track->{dimensions}{c}, 'analysis_group', 'Dimension C');
  is($track->{subGroup1}{name}, 'experiment', 'Subgroup1 name');
  is($track->{subGroup1}{label}, 'Experiment', 'Subgroup1 label');
  is($track->{subGroup1}{H3K4me1}, 'H3K4me1', 'Subgroup1 tag');
  is($track->{visibility}, 'dense', 'Correct visibility');

  # a random track
  note("Checking random track (bpHistoneModsC0010KH1H3K36me3MACS2_broad_peakEMBL-EBI)");
  $track = $tracks->{'bpHistoneModsC0010KH1H3K36me3MACS2_broad_peakEMBL-EBI'};
  ok($track, 'Track data exists');
  is($track->{shortLabel}, 'C0010K.K36me3.peak.mono', 'Correct shortLabel');
  is($track->{longLabel}, 
     'C0010K H3K36me3 MACS2_broad_peak CD14-positive, CD16-negative classical monocyte peak from NCMLS', 
     'Correct longLabel');
  is($track->{type}, 'bigbed', 'Correct type');
  like($track->{bigDataUrl}, qr/C0010KH1.H3K36me3.ppqt_macs2_broad_v2.+?bb$/, 'Correct bigDataUrl');
  # MOLECULE=genomic_DNA EPIRR_ID=IHECRE00000135.1 BIOMATERIAL_TYPE=Primary_Cell SAMPLE_ONTOLOGY_URI=http://purl.obolibrary.org/obo/CL_0002057;http://purl.obolibrary.org/obo/UBERON_0012168 SAMPLE_ID=ERS158623 EXPERIMENT_TYPE=H3K27me3 EXPERIMENT_ID=ERX190921 ALIGNMENT_SOFTWARE=BWA ANALYSIS_SOFTWARE=WIGGLER DONOR_ID=C00264 DONOR_SEX=Male DONOR_ETHNICITY=Northern_European CELL_TYPE=CD14-positive,_CD16-negative_classical_monocyte 
  my $metadata = $track->{metadata};
  is($metadata->{MOLECULE}, 'genomic_DNA', 'Correct MOLECULE metadata');
  like($metadata->{SAMPLE_ONTOLOGY_URI}, qr/UBERON_0013756/, 'Correct SAMPLE_ONTOLOGY_URI metadata');
  is($metadata->{CELL_TYPE}, 'CD14-positive,_CD16-negative_classical_monocyte', 'Correct CELL_TYPE metadata');

  note("Checking another random track (bpHistoneModsC00264H1H3K27me3MACS2_wigglerEMBL-EBIwiggler)");
  $track = $tracks->{'bpHistoneModsC00264H1H3K27me3MACS2_wigglerEMBL-EBIwiggler'};
  ok($track, 'Track data exists');
  is($track->{shortLabel}, 'C00264.K27me3.wig.mono', 'Correct shortLabel');
  is($track->{longLabel}, 
     'C00264 H3K27me3 MACS2_wiggler CD14-positive, CD16-negative classical monocyte signal from NCMLS', 
     'Correct longLabel');
  is($track->{type}, 'bigwig', 'Correct type');
  like($track->{bigDataUrl}, qr/C00264H1.H3K27me3\.wiggler\..+?bw$/, 'Correct bigDataUrl');
  # MOLECULE=genomic_DNA EPIRR_ID=IHECRE00000135.1 BIOMATERIAL_TYPE=Primary_Cell SAMPLE_ONTOLOGY_URI=http://purl.obolibrary.org/obo/CL_0002057;http://purl.obolibrary.org/obo/UBERON_0012168 SAMPLE_ID=ERS158623 EXPERIMENT_TYPE=H3K27me3 EXPERIMENT_ID=ERX190921 ALIGNMENT_SOFTWARE=BWA ANALYSIS_SOFTWARE=WIGGLER DONOR_ID=C00264 DONOR_SEX=Male DONOR_ETHNICITY=Northern_European CELL_TYPE=CD14-positive,_CD16-negative_classical_monocyte 
  $metadata = $track->{metadata};
  is($metadata->{EPIRR_ID}, 'IHECRE00000135.1', 'Correct EPIRR_ID metadata');
  is($metadata->{BIOMATERIAL_TYPE}, 'Primary_Cell', 'Correct metadata');
  is($metadata->{SAMPLE_ID}, 'ERS158623', 'Correct SAMPLE_ID metadata');
  
  #Test meta lines
  #my $test_line = '"Epigenome_Mnemonic"="BRST.HMEC" "Standardized_Epigenome_name"="HMEC Mammary Epithelial Primary Cells" "EDACC_Epigenome_name"="HMEC_Mammary_Epithelial" "Group"="<span style="color:#000000">ENCODE2012</span>" "Age"="" "Lab"="BI" "Sex"="Unknown" "Anatomy"="BREAST" "EID"="E119" "Type"="PrimaryCulture" "Order"="117" "Ethnicity"=""';
  my $test_line = '"Epigenome_Mnemonic"="BRST.HMEC" "Standardized_Epigenome_name"="HMEC Mammary Epithelial Primary Cells" "Have.dot.in.key"="Ignored"';
  my $valid_pair = $parser->_get_key_value_tokens($test_line);
  
  is($valid_pair->{'Epigenome_Mnemonic'}, "BRST.HMEC", 'Got back the right value for Epigenome_Mnemonic');
  is($valid_pair->{'Standardized_Epigenome_name'}, "HMEC Mammary Epithelial Primary Cells", 'Got back the right value for Standardized_Epigenome_name');
  is($valid_pair->{'Have.dot.in.key'}, undef, 'Ignored Have.dot.in.key');
  
  #"Cell_type/Tissue"="Mobilized_CD56_Primary_Cells" "FRAGLEN"="165" "NSC (Signal to noise)"="1.321089" "File_name"="UW.Mobilized_CD56_Primary_Cells.ChromatinAccessibility.RO_01689.DS16376.filt.tagAlign.gz" "Lab"="UW" "Control_file_name"="" "NREADS (36 bp mappability filtered)"="36048954" "Donor"="RO_01689.DS16376" "RSC (Phantom Peak)"="1.261162"
  my $test_line2 = '"Cell_type/Tissue"="Mobilized_CD56_Primary_Cells" "FRAGLEN"="165" "NSC (Signal to noise)"="1.321089" "File_name"="UW.Mobilized_CD56_Primary_Cells.ChromatinAccessibility.RO_01689.DS16376.filt.tagAlign.gz" "Lab"="UW" "Control_file_name"="" "NREADS (36 bp mappability filtered)"="36048954" "Donor"="RO_01689.DS16376" "RSC (Phantom Peak)"="1.261162"';
  my $expected_valid_pair2 = {
          'FRAGLEN' => '165',
          'Lab' => 'UW',
          'Cell_type/Tissue' => 'Mobilized_CD56_Primary_Cells',
          'File_name' => 'UW.Mobilized_CD56_Primary_Cells.ChromatinAccessibility.RO_01689.DS16376.filt.tagAlign.gz',
          'Donor' => 'RO_01689.DS16376'
        };
  
  my $got_valid_pair2 = $parser->_get_key_value_tokens($test_line2);
  cmp_deeply($got_valid_pair2, $expected_valid_pair2, "Parsed test_line2 correctly");
  
  #text with html in it
  my $test_line3='"Epigenome_Mnemonic"="GI.CLN.MUC" "Standardized_Epigenome_name"="Colonic Mucosa" "EDACC_Epigenome_name"="Colonic_Mucosa" "Group"="<span style="color:#C58DAA">Digestive</span>" "Age"="73Y" "Lab"="BI" "Sex"="Female" "Anatomy"="GI_COLON" "EID"="E075" "Type"="PrimaryTissue" "Order"="94" "Ethnicity"="Caucasian"';
  my $got_valid_pair3 = $parser->_get_key_value_tokens($test_line3);
  my $expected_valid_pair3 = {
  		  'Epigenome_Mnemonic' => 'GI.CLN.MUC',
          'Anatomy' => 'GI_COLON',
          'Age' => '73Y',
          'EDACC_Epigenome_name' => 'Colonic_Mucosa',
          'EID' => 'E075',
          'Sex' => 'Female',
          'Ethnicity' => 'Caucasian',
          'Group' => 'Digestive',
          'Order' => '94',
          'Type' => 'PrimaryTissue',
          'Standardized_Epigenome_name' => 'Colonic Mucosa',
          'Lab' => 'BI'
  };
  my $got_valid_pair3 = $parser->_get_key_value_tokens($test_line3);
  cmp_deeply($got_valid_pair3, $expected_valid_pair3, "Parsed test_line3 correctly");
   
  my $test_line4='GEO_Accession="<a href=http://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSM1127100 target=_blank>GSM1127100</a>" sample_alias="Breast Fibroblast RM071, batch 1" sample_common_name="Breast, Fibroblast Primary Cells" disease=None biomaterial_provider="Thea Tlsty lab" biomaterial_type="Primary Cell Culture" cell_type=Fibroblast markers=N/A culture_conditions=Trizol donor_id=RM071 donor_age=17 donor_health_status="Disease Free" donor_sex=Female donor_ethnicity="African American" passage_if_expanded=N/A batch=1 experiment_type=mRNA-Seq extraction_protocol="BCCAGSC mRNA Standard Operating Procedure" extraction_protocol_mrna_enrichment="Miltenyi-Biotec MACS mRNA purification" rna_preparation_initial_rna_qlty="RIN 9.7" rna_preparation_initial_rna_qnty="4 ug" rna_preparation_reverse_transcription_primer_sequence=NNNNNN rna_preparation_reverse_transcription_protocol="Invitrogen Superscript II RT" library_generation_pcr_template=cDNA library_fragmentation="COVARIS E210" library_fragment_size_range="266-470 bp" library_generation_pcr_polymerase_type=Phusion library_generation_pcr_thermocycling_program="98C 30 sec, 10 cycle of 98C 10 sec, 65C 30 sec, 72C 30 sec, then 72C 5 min, 4C hold" library_generation_pcr_number_cycles=10 library_generation_pcr_f_primer_sequence=AATGATACGGCGACCACCGAGATCTACACTCTTTCCCTACACGACGCTCTTCCGATCT library_generation_pcr_r_primer_sequence=CAAGCAGAAGACGGCATACGAGATCGGTCTCGGCATTCCTGCTGAACCGCTCTTCCGATCT library_generation_pcr_primer_conc="0.5 uM" library_generation_pcr_product_isolation_protocol="8% Novex TBE PAGE gel purification" dateUnrestricted=2014-04-15';
  my $got_valid_pair4 = $parser->_get_key_value_tokens($test_line4);
  my $expected_valid_pair4 = {
          'donor_id' => 'RM071',
          'donor_ethnicity' => 'African American',
          'donor_sex' => 'Female',
          'library_generation_pcr_primer_conc' => '0.5 uM',
          'rna_preparation_reverse_transcription_primer_sequence' => 'NNNNNN',
          'library_generation_pcr_f_primer_sequence' => 'AATGATACGGCGACCACCGAGATCTACACTCTTTCCCTACACGACGCTCTTCCGATCT',
          'rna_preparation_initial_rna_qlty' => 'RIN 9.7',
          'library_generation_pcr_number_cycles' => '10',
          'disease' => 'None',
          'donor_age' => '17',
          'sample_common_name' => 'Breast, Fibroblast Primary Cells',
          'library_fragmentation' => 'COVARIS E210',
          'sample_alias' => 'Breast Fibroblast RM071, batch 1',
          'library_generation_pcr_polymerase_type' => 'Phusion',
          'biomaterial_type' => 'Primary Cell Culture',
          'extraction_protocol_mrna_enrichment' => 'Miltenyi-Biotec MACS mRNA purification',
          'GEO_Accession' => 'GSM1127100',
          'library_generation_pcr_thermocycling_program' => '98C 30 sec, 10 cycle of 98C 10 sec, 65C 30 sec, 72C 30 sec, then 72C 5 min, 4C hold',
          'dateUnrestricted' => '2014-04-15',
          'passage_if_expanded' => 'N/A',
          'library_generation_pcr_template' => 'cDNA',
          'library_generation_pcr_product_isolation_protocol' => '8% Novex TBE PAGE gel purification',
          'experiment_type' => 'mRNA-Seq',
          'library_generation_pcr_r_primer_sequence' => 'CAAGCAGAAGACGGCATACGAGATCGGTCTCGGCATTCCTGCTGAACCGCTCTTCCGATCT',
          'rna_preparation_initial_rna_qnty' => '4 ug',
          'library_fragment_size_range' => '266-470 bp',
          'rna_preparation_reverse_transcription_protocol' => 'Invitrogen Superscript II RT',
          'batch' => '1',
          'culture_conditions' => 'Trizol',
          'extraction_protocol' => 'BCCAGSC mRNA Standard Operating Procedure',
          'cell_type' => 'Fibroblast',
          'markers' => 'N/A',
          'donor_health_status' => 'Disease Free',
          'biomaterial_provider' => 'Thea Tlsty lab'
        };
  cmp_deeply($got_valid_pair4, $expected_valid_pair4, "Parsed test_line4 correctly");
  
  
}


done_testing();

__END__
