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
