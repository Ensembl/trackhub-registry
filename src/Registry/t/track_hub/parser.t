# Copyright [2015-2017] EMBL-European Bioinformatics Institute
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
  
}

done_testing();
