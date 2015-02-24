#
# A class to represent a translator from UCSC-style trackdb
# documents to the corresponding JSON specification
#
package Registry::TrackHub::Translator;

use strict;
use warnings;

use JSON;
use Catalyst::Exception;

use Registry::TrackHub;
use Registry::TrackHub::Parser;

use vars qw($AUTOLOAD, $synonym2assembly);

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;

  return $self->{$attr};
}

sub new {
  my ($class, %args) = @_;
  
  defined $args{version} or Catalyst::Exception->throw("Undefined version");

  my $self = \%args;
  bless $self, $class;

  return $self;
}

#
# TODO
# validate JSON docs, use Registry->config()->{TrackHub}{json}{schema};
#
sub translate {
  my ($self, $url, $assembly) = @_;

  my $dispatch = 
    {
     '1.0' => sub { $self->to_json_1_0(@_) }
    }->{$self->version};

  Catalyst::Exception->throw(sprintf "Version %d not supported", $self->version) 
      unless $dispatch;

  my $trackhub = Registry::TrackHub->new(url => $url);
  
  my $docs;
  unless ($assembly) { 
    # assembly not specified
    # translate tracksDB conf for all assemblies stored in the Hub
    foreach my $assembly ($trackhub->assemblies) {
      push @{$docs}, $dispatch->(trackhub => $trackhub, 
				 assembly => $assembly);
    }
  } else {
    push @{$docs}, $dispatch->(trackhub => $trackhub, 
			       assembly => $assembly);
  }

  scalar @{$docs} or 
    Catalyst::Exception->throw("Something went wrong. Couldn't get any translated JSON from hub");

  return $docs;
}

sub to_json_1_0 {
  my ($self, %args) = @_;
  my ($trackhub, $assembly) = ($args{trackhub}, $args{assembly});
  defined $trackhub and defined $assembly or
    Catalyst::Exception->throw("Undefined trackhub and/or assembly argument");

  my $genome = $trackhub->get_genome($assembly);

  my $doc = 
    {
     version => '1.0',
     hub     => $trackhub->longLabel,
     # add the original trackDb file(s) content
     # trackdb => $genome->get_trackdb_content
    };

  # add species/assembly information
  $self->_add_genome_info($genome, $doc);

  # now the tracks, metadata and display/configuration
  my $tracks = Registry::TrackHub::Parser->new(files => $genome->trackDb)->parse;

  foreach my $track (keys %{$tracks}) {
    my $metadata = { id => $track, 
		     # longLabel should be present since mandatory for UCSC
		     name => $tracks->{$track}{longLabel} }; 
    map { $metadata->{$_} = $tracks->{$track}{metadata}{$_} }
      keys %{$tracks->{$track}{metadata}};
    push @{$doc->{data}}, $metadata;

    delete $tracks->{$track}{metadata};
    map { $doc->{configuration}{$track}{$_} = $tracks->{$track}{$_} }
      keys %{$tracks->{$track}};
  }

  return to_json($doc);
}

#
# TODO
#
# Add species/assembly info
#
# I presume this can be shared across translations
# to different versions
#

$synonym2assembly = 
  {
   #
   # Mammals
   #
   # human
   hg38 => 'GRCh38',
   hg19 => 'GRCh37',
   hg18 => 'NCBI36',
   hg17 => 'NCBI35',
   hg16 => 'NCBI34',
   # alpaca
   vicPac2 => 'Vicugna_pacos-2.0.1',
   vicPac1 => 'VicPac1.0',
   # armadillo
   dasNov3 => 'Dasnov3.0',
   # bushbaby
   otoGar3 => 'OtoGar3', # not found on NCBI
   # baboon
   papHam1 => 'Pham_1.0', # not found on NCBI
   papAnu2 => 'Panu_2.0',
   # cat
   felCat5 => 'Felis_catus-6.2',
   felCat4 => 'catChrV17e',
   # felCat3 => ? no name found
   # chimp
   panTro4 => 'Pan_troglodytes-2.1.4',
   panTro3 => 'Pan_troglodytes-2.1.3',
   panTro2 => 'Pan_troglodytes-2.1', # no synonym reported by NCBI
   # panTro1 => '', # not found
   # chinese hamster
   criGri1 => 'C_griseus_v1.0', # no synonym reported by NCBI
   # cow
   bosTau8 => 'Bos_taurus_UMD_3.1.1', # no synonym reported by NCBI
   bosTau7 => 'Btau_4.6.1',
   bosTau6 => 'Bos_taurus_UMD_3.1', # no synonym reported by NCBI
   bosTau4 => 'Btau_4.0',
   bosTau3 => 'Btau_3.1', # no synonym reported by NCBI
   bosTau2 => 'Btau_2.0', # no Btau_2.0 entry in NCBI
   bosTau1 => 'Btau_1.0', # no Btau_1.0 entry in NCBI
   # dog
   canFam3 => 'CanFam3.1',
   canFam2 => 'CanFam2.0',
   # canFam1 => '', # not found on NCBI
   # dolphin
   turTru2 => 'Ttru_1.4' # not found on NCBI
   # elephant
   loxAfr3 => 'Loxafr3.0',
   # ferret
   musFur1 => 'MusPutFur1.0',
   # gibbon
   nomLeu3 => 'Nleu_3.0',
   nomLeu2 => 'Nleu1.1', # no Nleu1.1 found on NCBI
   nomLeu1 => 'Nleu1.0', # no Nleu1.0 found on NCBI
   # gorilla
   gorGor3 => 'gorGor3.1',
   # guinea pig
   cavPor3 => 'Cavpor3.0',
   # hedgehog
   # eriEur2 => 'EriEur2.0', # no hedgehog data on NCBI
   # eriEur1 => '',
   # horse
   equCab2 => 'EquCab2.0',
   # equCab1 => 'EquCab1.0', # no EquCab1.0 entry on NCBI
   # kangaroo rat, not found
   # dipOrd1 => 'DipOrd1.0',
   # manatee, not found
   # triMan1 => 'TriManLat1.0',
   # marmoset, not found
   # calJac3 => 'Callithrix_jacchus-v3.2',
   # calJac1 => 'Callithrix_jacchus-v2.0.2',
   # megabat, not found
   # pteVam1 => 'Ptevap1.0',
   # microbat, not found
   # myoLuc2 => 'MyoLuc2.0',
   # minke whale
   balAcu1 => 'BalAcu1.0', # no synonym in NCBI
   # mouse
   mm10 => 'GRCm38',
   mm9 => 'MGSCv37',
   mm8 => 'MGSCv36',
   mm7 => 'MGSCv35',
   # mm6 => 'MGSCv34', # no MGSCv34 entry
   # mm5 => 'MGSCv33', # no MGSCv33 entry
   # mm4 => 'MGSCv32', # no MGSCv32 entry
   # mm3 => 'MGSCv30', # no MGSCv30 entry
   # mm2 => 'MGSCv3', # no MGSCv3 entry
   # mm1 => 'MGSCv2', # no MGSCv2 entry
   # mouse lemur, not found
   # micMur1 => 'MicMur1.0',
   # naked mole rat
   hetGla2 => 'HetGla_female_1.0',
   hetGla1 => 'HetGla_1.0', # no synonym on NCBI
   # opossum, not found
   # monDom5 => 'MonDom5',
   # monDom4 => 'MonDom4',
   # monDom1 => 'MonDom1',
   # orangutan
   # ponAbe2 => 'Pongo_albelii-2.0.2', # NCBI reports the following
   ponAbe2 => 'P_pygmaeus_2.0.2',
   # panda, not found
   # ailMel1 => 'AilMel 1.0',
   # pig
   susScr3 => 'Sscrofa10.2',
   susScr2 => 'Sscrofa9.2', # no syn on NCBI
   # pika, not found
   # ochPri3 => 'OchPri3.0',
   # ochPri2 => 'OchPri2',
   # platypus
   ornAna1 => 'Ornithorhynchus_anatinus-5.0.1', # no syn on NCBI
   # rabbit
   oryCun2 => 'OryCun2.0',
   # rat
   rn6 => 'Rnor_6.0',
   rn5 => 'Rnor_5.0',
   rn4 => 'RGSC_v3.4', # no syn on NCBI
   # rn3 => 'RGSC_v3.1', # not found
   # rn2 => 'RGSC_v2.1', # not found
   # rn1 => 'RGSC_v1.0', # not found
   hetGla2 => 'HetGla_female_1.0', # not reported by UCSC
   # rhesus, not found
   # rheMac3 => 'CR_1.0',
   # rheMac2 => 'v1.0 Mmul_051212',
   # rheMac1 => 'Mmul_0.1',
   # rock hyrax
   proCap1 => 'Procap1.0',
   # sheep
   oviAri3 => 'Oar_v3.1',
   # oviAri1 => '', # not found
   # shrew, not found
   # sorAra2 => 'SorAra2.0',
   # sorAra1 => 'SorAra1.0',
   # sloth, not found
   # choHof1 => 'ChoHof1.0',
   # squirrel
   # speTri2 => 'SpeTri2.0', # no SpeTri2.0 on NCBI
   # squirrel monkey, not found
   # saiBol1 => 'SaiBol1.0',
   # tarsier
   tarSyr1 => 'Tarsyr1.0',
   # tasmanian devil
   sarHar1 => 'Devil_ref v7.0',
   # tenrec, not found
   # echTel2 => 'EchTel2.0',
   # echTel1 => 'echTel1',
   # tree shrew, not found
   # tupBel1 => 'Tupbel1.0',
   # wallaby
   macEug2 => 'Meug_1.1', # no syn on NCBI
   # white rhinoceros
   cerSim1 => 'CerSimSim1.0',
   #
   # Vertebrates
   #
   # american alligator
   allMis1 => 'allMis0.2',
   # atlantic cod
   gadMor1 => 'GadMor_May2010',
   # budgerigar
   melUnd1 => 'elopsittacus_undulatus_6.3',
   # chicken
   galGal4 => 'Gallus_gallus-4.0',
   galGal3 => 'Gallus_gallus-2.1',
   # galGal2 => 'Gallus-gallus-1.0', # no Gallus-gallus-1.0 on NCBI
   # coelacanth
   latCha1 => 'LatCha1',
   # elephant shark
   calMil1 => 'Callorhinchus_milli_6.1.3', # no syn on NCBI
   # fugu
   fr3 => 'FUGU5',
   # fr2 => '', # not found
   # fr1 => '', # not found
   # lamprey, not found
   # petMar2 => '',
   # petMar1 => '',
   # lizard, not found
   # anoCar2 => 'AnoCar2',
   # anoCar1 => 'AnoCar1',
   # medaka
   # oryLat2 => '', # not found
   # medium ground finch
   geoFor1 => 'GeoFor_1.0', # no syn on NCBI
   # nile tilapia
   oreNil2 => 'Orenil1.1',
   # painted turtle
   chrPic1 => 'Chrysemys_picta_bellii-3.0.1',
   # stickleback, not found
   # gasAcu1 => '',
   # tetraodon
   # tetNig2 => '',
   # tetNig1 => '',
   # turkey
   melGal1 => 'Turkey_2.01',
   # xenopus tropicalis
   xenTro3 => 'v4.2',
   # xenTro2 => 'v4.1', # not found
   # xenTro2 => 'v3.0', # not found
   # zebra finch
   # taeGut2 => '', # not found
   taeGut1 => 'Taeniopygia_guttata-3.2.4',
   # zebrafish
   danRer7 => 'Zv9',
   danRer6 => 'Zv8', # no syn on on NCBI
   danRer5 => 'Zv7',
   # danRer4 => 'Zv6', # not found on NCBI
   # danRer3 => 'Zv5', # not found on NCBI
   # danRer2 => 'Zv4', # not found on NCBI
   # danRer1 => 'Zv3', # not found on NCBI
   #
   # Deuterostomes
   #
   # C. intestinalis
   # ci2 => '', # not found
   ci1 => 'v1.0',
   # lancelet, not found
   # braFlo1 => '',
   # Strongylocentrotus purpuratus
   strPur2 => 'Spur_v2.1',
   strPur1 => 'Spur_0.5', # no syn on NCBI
   #
   # Insects
   #
   # Apis mellifera
   apiMel2 => 'Amel_2.0', # no syn on NCBI
   # apiMel1 => 'v.Amel_1.2', # no v.Amel_1.2 entry on NCBI
   # Anopheles gambiae
   # anoGam1 => 'v.MOZ2', # not found
   # Drosophila ananassae
   droAna3 => 'dana_caf1', # no droAna3 UCSC syn
   # droAna2 => '', # not found
   # droAna1 => '', # not found
   # Drosophila erecta
   droEre2 => 'dere_caf1', # no droEre2 UCSC syn
   # droEre1 => '', # not found
   # Drosophila grimshawi
   droGri2 => 'dgri_caf1', # no droGri2 UCSC syn
   droGri1 => '', # not found
   # Drosophila melanogaster
   dm6 => 'Release 6 plus ISO1 MT',
   dm3 => 'Release 5',
   # dm2 => 'Release 4', # no Release 4 
   # dm1 => 'Release 3', # no Release 3
   # Drosophila mojavensis
   droMoj3 => 'dmoj_caf1', # no droMoj3 UCSC syn
   # droMoj2 => '', # not found
   # droMoj1 => '', # not found
   # Drosophila persimilis
   droPer1 => 'dper_caf1',
   # Drosophila pseudoobscura, not found
   # dp3 => '',
   # dp2 => '',
   # Drosophila sechellia
   droSec1 => 'dsec_caf1',
   # Drosophila simulans
   droSim1 => 'dsim_caf1', # not sure, several v1 for different strains on NCBI
   # Drosophila virilis
   droVir3 => 'dvir_caf1', # no droVir3 UCSC syn
   # droVir2 => '', # not found
   # droVir1 => '', # not found
   # Drosophila yakuba
   # droYak2 => '', # not found
   # droYak1 => '', # not found
   #
   # Nematodes
   #
   # Caenorhabditis brenneri
   caePb2 => 'C_brenneri-6.0.1', # not sure (not 2008)
   # caePb1 => '', # not found
   # Caenorhabditis briggsae 
   cb3 => 'Cb3',
   # cb1 => '', # not found
   # Caenorhabditis elegans
   ce10 => 'WBcel215',
   # ce6  => '', # not found
   # ce4  => '',
   # ce2  => '',
   # ce1  => '',
   # Caenorhabditis japonica
   # caeJap1 => '', # not found
   # Caenorhabditis remanei
   # caeRem3 => '', # not found
   # caeRem2 => '',
   # Pristionchus pacificus
   # priPac1 => '', # not found
   #
   # Other
   #
   # sea hare
   aplCal1 => 'Aplcal2.0',
   # Yeast
   sacCer3 => 'R64-1-1',
   # sacCer2 => '', # not found
   # sacCer1 => '', # not found
   # ebola virus
   # eboVir3 => '', # not found
  };

sub _add_genome_info {
  my ($self, $genome, $doc) = @_;

  $doc->{species}{taxid} = 9606;
  $doc->{species}{scientific_name} = 'Homo sapiens';

  $doc->{assembly}{name} = 'GRCh37';
  $doc->{assembly}{accession} = 'GCA_000001405.1';
  $doc->{assembly}{synonyms} = 'hg19';
}

1;
