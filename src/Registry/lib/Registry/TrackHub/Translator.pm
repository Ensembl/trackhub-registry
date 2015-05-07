#
# A class to represent a translator from UCSC-style trackdb
# documents to the corresponding JSON specification
#
package Registry::TrackHub::Translator;

use strict;
use warnings;

use JSON;
use Registry::GenomeAssembly::Schema;
use Registry::TrackHub;
use Registry::TrackHub::Tree;
use Registry::TrackHub::Parser;

use vars qw($AUTOLOAD $synonym2assembly);

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
  
  defined $args{version} or die "Undefined version";

  my $self = \%args;

  # TODO: Load the GCAssemblySet from the catalyst model which reads
  #       the connection parameters from the configuration file
  my $gcschema = 
    Registry::GenomeAssembly::Schema->connect("DBI:Oracle:host=ora-vm5-003.ebi.ac.uk;sid=ETAPRO;port=1571", 
					      'gc_reader', 
					      'reader', 
					      { 'RaiseError' => 1, 'PrintError' => 0 });
  $self->{gc_assembly_set} = $gcschema->resultset('GCAssemblySet');
  bless $self, $class;

  return $self;
}

sub translate {
  my ($self, $url, $assembly) = @_;

  my $dispatch = 
    {
     'v1.0' => sub { $self->to_json_1_0(@_) }
    }->{$self->version};

  die sprintf "Version %s not supported", $self->version
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
    die "Something went wrong. Couldn't get any translated JSON from hub";

  return $docs;
}

##################################################################################
#             
# Version v1.0 
#             
sub to_json_1_0 {
  my ($self, %args) = @_;
  my ($trackhub, $assembly) = ($args{trackhub}, $args{assembly});
  defined $trackhub and defined $assembly or
    die "Undefined trackhub and/or assembly argument";

  my $genome = $trackhub->get_genome($assembly);

  my $doc = 
    {
     version => 'v1.0',
     hub     => {
		 name => $trackhub->hub,
		 shortLabel => $trackhub->shortLabel,
		 longLabel => $trackhub->longLabel,
		},
     # add the original trackDb file(s) content
     # trackdb => $genome->get_trackdb_content
    };

  # add species/assembly information
  $self->_add_genome_info($genome, $doc);

  # now the tracks, metadata and display/configuration
  my $tracks = Registry::TrackHub::Parser->new(files => $genome->trackDb)->parse;

  # set each track metadata, prepare the configuration object
  foreach my $track (keys %{$tracks}) {
    # 
    # NOTE: at least a track can be searched by ID and NAME (longLabel)
    #
    my $metadata = { id => $track }; 
    # longLabel should be present since mandatory for UCSC
    # Do not rely on it, see Blueprint track db
    $metadata->{name} = $tracks->{$track}{longLabel} || $tracks->{$track}{shortLabel};
    # we don't want null attribute values, enforced in the schema
    delete $metadata->{name} unless defined $metadata->{name};

    # add specific metadata, if ever present
    map { $metadata->{$_} = $tracks->{$track}{metadata}{$_} if defined $tracks->{$track}{metadata}{$_} }
      keys %{$tracks->{$track}{metadata}};
    push @{$doc->{data}}, $metadata;

    delete $tracks->{$track}{metadata};
  }

  # set the configuration part of the document according to the track hierarchy,
  # i.e. composites should have members
  my $ctree = Registry::TrackHub::Tree->new({ id => 'root' });
  $self->_make_configuration_tree($ctree, $tracks);

  # now can recursively descend the hierarchy and 
  # build the configuration object
  map { $doc->{configuration}{$_->id} = $self->_make_configuration_object_1_0($_) } 
    @{$ctree->child_nodes};
  
  return to_json($doc, { utf8 => 1, pretty => 1 });
}


sub _make_configuration_object_1_0 {
  my ($self, $node) = @_;
  defined $node or die "Undefined args";
  
  # add the configuration attributes as they are specified
  my $node_conf = {};
  map { $node_conf->{$_} = $node->data->{$_} } keys %{$node->data};
  # delete $node_conf->{track};

  # now add the configuration of the children, if any
  for my $child (@{$node->child_nodes}) {
    my $child_conf = $self->_make_configuration_object_1_0($child);
    $node_conf->{members}{$child_conf->{track}} = $child_conf;
  }

  return $node_conf;
}
#
##################################################################################


sub _make_configuration_tree {
  my ($self, $tree, $tracks) = @_;
  defined $tree or die "Undefined tree";
  defined $tracks or die "Undefined tracks";

  my %redo;
  foreach (sort { !$b->{'parent'} <=> !$a->{'parent'} } values %$tracks) {
    if ($_->{'parent'}) {
      my $parent = $tree->get_node($_->{'parent'});
      
      if ($parent) {
        $parent->append($tree->create_node($_->{'track'}, $_));
      } else {
        $redo{$_->{'track'}} = $_;
      }
    } else {
      $tree->append($tree->create_node($_->{'track'}, $_));
    }
  }

  $self->_make_configuration_tree($tree, \%redo) 
    if scalar keys %redo;
}

#
# TODO?
# Move to a configuration file?
#
# A map from UCSC assembly db names to NCBI assembly set accessions
#
# I presume this can be shared across translations
# to different versions
#
$synonym2assembly = 
  {
   #
   # These mappings have been derived from the list of UCSC genome releases at:
   # https://genome.ucsc.edu/FAQ/FAQreleases.html
   #
   # Mammals
   #
   # human
   hg38 => 'GCA_000001405.15', # 'GRCh38',
   hg19 => 'GCA_000001405.1', # 'GRCh37',
   hg18 => 'GCF_000001405.12', #'NCBI36',
   hg17 => 'GCF_000001405.11', # 'NCBI35',
   hg16 => 'GCF_000001405.10', # 'NCBI34',
   # alpaca
   vicPac2 => 'GCA_000164845.2', # 'Vicugna_pacos-2.0.1',
   vicPac1 => 'GCA_000164845.1', # 'VicPac1.0', # no NCBI syn
   # armadillo
   dasNov3 => 'GCA_000208655.2', # 'Dasnov3.0',
   # bushbaby
   otoGar3 => 'GCA_000181295.3', # 'OtoGar3',
   # baboon
   # papHam1 => 'Pham_1.0', # not found on NCBI
   papAnu2 => 'GCA_000264685.1', # 'Panu_2.0',
   # cat
   felCat5 => 'GCA_000181335.2', # 'Felis_catus-6.2',
   felCat4 => 'GCA_000003115.1', # 'catChrV17e',
   # felCat3 => '', # no name found
   # chimp
   panTro4 => 'GCA_000001515.4', # 'Pan_troglodytes-2.1.4',
   panTro3 => 'GCA_000001515.3', # 'Pan_troglodytes-2.1.3',
   panTro2 => 'GCF_000001515.3', # 'Pan_troglodytes-2.1', # no syn on NCBI
   # panTro1 => '', # not found
   # chinese hamster
   criGri1 => 'GCA_000419365.1', # 'C_griseus_v1.0', # no syn on NCBI
   # cow
   bosTau8 => 'GCA_000003055.5', # 'Bos_taurus_UMD_3.1.1', # no syn on NCBI
   bosTau7 => 'GCA_000003205.4', # 'Btau_4.6.1',
   bosTau6 => 'GCA_000003055.3', # 'Bos_taurus_UMD_3.1', # no synonym reported by NCBI
   bosTau4 => 'GCF_000003205.2', # 'Btau_4.0',
   bosTau3 => 'GCF_000003205.1', # 'Btau_3.1', # no synonym reported by NCBI
   # bosTau2 => 'Btau_2.0', # no Btau_2.0 entry in NCBI
   # bosTau1 => 'Btau_1.0', # no Btau_1.0 entry in NCBI
   # dog
   canFam3 => 'GCA_000002285.2', # 'CanFam3.1',
   canFam2 => 'GCA_000002285.1', # 'CanFam2.0',
   # canFam1 => '', # not found on NCBI
   # dolphin
   turTru2 => 'GCA_000151865.2', # 'Ttru_1.4'
   # elephant
   loxAfr3 => 'GCA_000001905.1', # 'Loxafr3.0',
   # ferret
   musFur1 => 'GCA_000215625.1', # 'MusPutFur1.0',
   # gibbon
   nomLeu3 => 'GCA_000146795.3', # 'Nleu_3.0',
   nomLeu2 => 'GCA_000146795.2', # 'Nleu1.1',
   nomLeu1 => 'GCA_000146795.1', # 'Nleu1.0', 
   # gorilla
   gorGor3 => 'GCA_000151905.1', # 'gorGor3.1',
   # guinea pig
   cavPor3 => 'GCA_000151735.1', # 'Cavpor3.0',
   # hedgehog
   eriEur2 => 'GCA_000296755.1', # 'EriEur2.0', # no syn on NCBI
   # eriEur1 => 'Draft_v1', # no Draft_v1 entry in NCBI
   # horse
   equCab2 => 'GCA_000002305.1', # 'EquCab2.0',
   # equCab1 => 'EquCab1.0', # no EquCab1.0 entry on NCBI
   # kangaroo rat (Dipodomys merriami), not found
   # dipOrd1 => 'DipOrd1.0',
   # manatee
   triMan1 => 'GCA_000243295.1', # 'TriManLat1.0',
   # marmoset
   calJac3 => 'GCA_000004665.1', # 'Callithrix_jacchus-v3.2',
   # calJac1 => 'Callithrix_jacchus-v2.0.2', # no Callithrix_jacchus-v2.0.2 entry on NCBI
   # megabat
   pteVam1 => 'GCA_000151845.1', # 'Ptevap1.0',
   # microbat
   myoLuc2 => 'GCA_000147115.1', # 'Myoluc2.0',
   # minke whale
   balAcu1 => 'GCA_000493695.1', # 'BalAcu1.0', # no synonym in NCBI
   # mouse
   mm10 => 'GCA_000001635.2', # 'GRCm38',
   mm9 => 'GCA_000001635.1', # 'MGSCv37',
   mm8 => 'GCF_000001635.15', # 'MGSCv36',
   mm7 => 'GCF_000001635.14', # 'MGSCv35',
   # mm6 => 'MGSCv34', # no MGSCv34 entry
   # mm5 => 'MGSCv33', # no MGSCv33 entry
   # mm4 => 'MGSCv32', # no MGSCv32 entry
   # mm3 => 'MGSCv30', # no MGSCv30 entry
   # mm2 => 'MGSCv3', # no MGSCv3 entry
   # mm1 => 'MGSCv2', # no MGSCv2 entry
   # mouse lemur
   micMur1 => 'GCA_000165445.1', # 'ASM16544v1', # no MicMur1.0 entry on NCBI
   # naked mole rat
   hetGla2 => 'GCA_000247695.1', # 'HetGla_female_1.0',
   hetGla1 => 'GCA_000230445.1', # 'HetGla_1.0', # no synonym on NCBI
   # opossum
   monDom5 => 'GCF_000002295.2', # 'MonDom5',
   # monDom4 => 'MonDom4', # no MonDom4 entry
   # monDom1 => 'MonDom1', # no MonDom1 entry
   # orangutan
   # ponAbe2 => 'Pongo_albelii-2.0.2', # NCBI reports instead
   ponAbe2 => 'GCA_000001545.3', # 'P_pygmaeus_2.0.2',
   # panda
   ailMel1 => 'GCA_000004335.1', # 'AilMel_1.0',
   # pig
   susScr3 => 'GCA_000003025.4', # 'Sscrofa10.2',
   susScr2 => 'GCA_000003025.2', # 'Sscrofa9.2', # no syn on NCBI
   # pika
   ochPri3 => 'GCA_000292845.1', # 'OchPri3.0', # no syn on NCBI
   # ochPri2 => 'OchPri2', # NCBI reports instead
   ochPri2 => 'GCA_000164825.1', # 'ASM16482v1', 
   # platypus
   ornAna1 => 'GCF_000002275.2', # 'Ornithorhynchus_anatinus-5.0.1', # no syn on NCBI
   # rabbit
   oryCun2 => 'GCA_000003625.1', # 'OryCun2.0',
   # rat
   rn6 => 'GCA_000001895.4', # 'Rnor_6.0',
   rn5 => 'GCA_000001895.3', # 'Rnor_5.0',
   rn4 => 'GCF_000001895.3', # 'RGSC_v3.4', # no syn on NCBI
   # rn3 => 'RGSC_v3.1', # not found
   # rn2 => 'RGSC_v2.1', # not found
   # rn1 => 'RGSC_v1.0', # not found
   # rhesus (Macaca mulatta)
   rheMac3 => 'GCA_000230795.1', # 'CR_1.0',
   rheMac2 => 'GCA_000002255.1', # 'Mmul_051212',
   # rheMac1 => 'Mmul_0.1', # not found
   # rock hyrax
   proCap1 => 'GCA_000152225.1', # 'Procap1.0',
   # sheep
   oviAri3 => 'GCA_000298735.1', # 'Oar_v3.1',
   # oviAri1 => '', # not found
   # shrew
   sorAra2 => 'GCA_000181275.2', # 'SorAra2.0',
   # sorAra1 => 'SorAra1.0', # not found
   # sloth
   choHof1 => 'GCA_000164785.1', # 'ChoHof1.0',
   # squirrel
   speTri2 => 'GCA_000236235.1', # 'SpeTri2.0',
   # squirrel monkey
   saiBol1 => 'GCA_000235385.1', # 'SaiBol1.0',
   # tarsier
   tarSyr1 => 'GCA_000164805.1', # 'Tarsyr1.0',
   # tasmanian devil
   sarHar1 => 'GCA_000189315.1', # 'Devil_ref v7.0',
   # tenrec
   echTel2 => 'GCA_000313985.1', # 'EchTel2.0',
   # echTel1 => 'echTel1', # not found
   # tree shrew
   # tupBel1 => 'Tupbel1.0', # no Tupebel1.0 found
   # wallaby
   macEug2 => 'GCA_000004035.1', # 'Meug_1.1', # no syn on NCBI
   # white rhinoceros
   cerSim1 => 'GCA_000283155.1', # 'CerSimSim1.0',
   #
   # Vertebrates
   #
   # american alligator
   allMis1 => 'GCA_000281125.1', # 'allMis0.2',
   # atlantic cod
   gadMor1 => 'GCA_000231765.1', # 'GadMor_May2010',
   # budgerigar
   melUnd1 => 'GCA_000238935.1', # 'Melopsittacus_undulatus_6.3',
   # chicken
   galGal4 => 'GCA_000002315.2', # 'Gallus_gallus-4.0',
   galGal3 => 'GCA_000002315.1', # 'Gallus_gallus-2.1',
   # galGal2 => 'Gallus-gallus-1.0', # no Gallus-gallus-1.0 on NCBI
   # coelacanth
   latCha1 => 'GCA_000225785.1', # 'LatCha1',
   # elephant shark
   calMil1 => 'GCA_000165045.2', # 'Callorhinchus_milli-6.1.3', # no syn on NCBI
   # fugu
   fr3 => 'GCA_000180615.2', # 'FUGU5',
   # fr2 => '', # not found
   # fr1 => '', # not found
   # lamprey
   petMar2 => 'GCA_000148955.1', # 'Petromyzon_marinus-7.0',
   # petMar1 => '', # not found
   # lizard (Anolis carolinensis)
   anoCar2 => 'GCA_000090745.2', # 'AnoCar2.0',
   # anoCar1 => 'AnoCar1', # not found
   # medaka
   # oryLat2 => '', # not found
   # medium ground finch
   geoFor1 => 'GCA_000277835.1', # 'GeoFor_1.0', # no syn on NCBI
   # nile tilapia
   oreNil2 => 'GCA_000188235.2', # 'Orenil1.1',
   # painted turtle
   chrPic1 => 'GCA_000241765.1', # 'Chrysemys_picta_bellii-3.0.1',
   # stickleback
   # gasAcu1 => '', # not found
   # tetraodon
   # tetNig2 => '',
   tetNig1 => 'GCA_000180735.1', # 'ASM18073v1',
   # turkey
   melGal1 => 'GCA_000146605.2', # 'Turkey_2.01',
   # xenopus tropicalis
   xenTro3 => 'GCA_000004195.1', # 'v4.2',
   # xenTro2 => 'v4.1', # not found
   # xenTro2 => 'v3.0', # not found
   # zebra finch
   # taeGut2 => '', # not found
   taeGut1 => 'GCA_000151805.2', # 'Taeniopygia_guttata-3.2.4',
   # zebrafish
   danRer7 => 'GCA_000002035.2', # 'Zv9',
   danRer6 => 'GCA_000002035.1', # 'Zv8', # no syn on on NCBI
   danRer5 => 'GCF_000002035.1', # 'Zv7',
   # danRer4 => 'Zv6', # not found on NCBI
   # danRer3 => 'Zv5', # not found on NCBI
   # danRer2 => 'Zv4', # not found on NCBI
   # danRer1 => 'Zv3', # not found on NCBI
   #
   # Deuterostomes
   #
   # C. intestinalis
   # ci2 => '', # not found
   ci1 => 'GCA_000183065.1', # 'v1.0',
   # lancelet, not found
   # braFlo1 => '',
   # Strongylocentrotus purpuratus
   strPur2 => 'GCF_000002235.2', # 'Spur_v2.1',
   strPur1 => 'GCF_000002235.1', # 'Spur_0.5', # no syn on NCBI
   #
   # Insects
   #
   # Apis mellifera
   apiMel2 => 'GCF_000002195.1', # 'Amel_2.0', # no syn on NCBI
   # apiMel1 => 'v.Amel_1.2', # no v.Amel_1.2 entry on NCBI
   # Anopheles gambiae
   # anoGam1 => 'v.MOZ2', # not found
   # Drosophila ananassae
   droAna3 => 'GCA_000005115.1', # 'dana_caf1', # no droAna3 UCSC syn
   # droAna2 => '', # not found
   # droAna1 => '', # not found
   # Drosophila erecta
   droEre2 => 'GCA_000005135.1', # 'dere_caf1', # no droEre2 UCSC syn
   # droEre1 => '', # not found
   # Drosophila grimshawi
   droGri2 => 'GCA_000005155.1', # 'dgri_caf1', # no droGri2 UCSC syn
   # droGri1 => '', # not found
   # Drosophila melanogaster
   dm6 => 'GCA_000001215.4', # 'Release 6 plus ISO1 MT',
   dm3 => 'GCA_000001215.2', # 'Release 5',
   # dm2 => 'Release 4', # no Release 4 
   # dm1 => 'Release 3', # no Release 3
   # Drosophila mojavensis
   droMoj3 => 'GCA_000005175.1', # 'dmoj_caf1', # no droMoj3 UCSC syn
   # droMoj2 => '', # not found
   # droMoj1 => '', # not found
   # Drosophila persimilis
   droPer1 => 'GCA_000005195.1', # 'dper_caf1',
   # Drosophila pseudoobscura, not found
   # dp3 => '',
   # dp2 => '',
   # Drosophila sechellia
   droSec1 => 'GCA_000005215.1', # 'dsec_caf1',
   # Drosophila simulans
   droSim1 => 'GCA_000259055.1', # 'dsim_caf1', # not sure, several v1 for different strains on NCBI
   # Drosophila virilis
   droVir3 => 'GCA_000005245.1', # 'dvir_caf1', # no droVir3 UCSC syn
   # droVir2 => '', # not found
   # droVir1 => '', # not found
   # Drosophila yakuba
   # droYak2 => '', # not found
   # droYak1 => '', # not found
   #
   # Nematodes
   #
   # Caenorhabditis brenneri
   caePb2 => 'GCA_000143925.1', # 'C_brenneri-6.0.1', # not sure (not 2008)
   # caePb1 => '', # not found
   # Caenorhabditis briggsae 
   cb3 => 'GCA_000004555.2', # 'Cb3',
   # cb1 => '', # not found
   # Caenorhabditis elegans
   ce10 => 'GCA_000002985.2', # 'WBcel215',
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
   aplCal1 => 'GCA_000002075.1', # 'Aplcal2.0',
   # Yeast
   sacCer3 => 'GCA_000146045.2', # 'R64-1-1',
   # sacCer2 => '', # not found
   # sacCer1 => '', # not found
   # ebola virus
   # eboVir3 => '', # not found
   #
   # And the following mappings have been derived by looking
   # the UCSC synonyms for the assemblies in the public hubs at:
   # http://genome.ucsc.edu/cgi-bin/hgHubConnect
   #
   # http://smithlab.usc.edu/trackdata/methylation/hub.txt
   #
   # Arabidopsis thaliana
   tair10 => 'GCA_000001735.1', # TAIR10
   tair9  => 'GCA_000001735.1', # TAIR9
   #
   # http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt
   #
   # Arabidopsis thaliana
   araTha1 => 'GCA_000001735.1', # TAIR10
   # Ricinus communis
   ricCom1 => 'GCA_000151685.2', # JCVI_RCG_1.1
   # brassica rapa
   braRap1 => 'GCA_000309985.1', # Brapa_1.0
   #
   # http://genome-test.cse.ucsc.edu/~nknguyen/ecoli/publicHubs/pangenome/hub.txt
   # http://genome-test.cse.ucsc.edu/~nknguyen/ecoli/publicHubs/pangenomeWithDups/hub.txt
   #
   # Escherichia coli 042
   EscherichiaColi042Uid161985 => 'GCA_000027125.1', # ASM2712v1
   # Escherichia coli 536
   EscherichiaColi536Uid58531 => 'GCA_000013305.1', # ASM1330v1
   # Escherichia coli 55989
   EscherichiaColi55989Uid59383 => 'GCA_000026245.1', # ASM2624v1
   # Escherichia coli ABU 83972
   EscherichiaColiAbu83972Uid161975 => 'GCA_000148365.1', # ASM14836v1
   # Escherichia coli APEC O1
   EscherichiaColiApecO1Uid58623 => 'GCA_000014845.1', # ASM1484v1
   # Escherichia coli ATCC 8739
   EscherichiaColiAtcc8739Uid58783 => 'GCA_000019385.1', # ASM1938v1 
   # Escherichia coli BL21 DE3
   EscherichiaColiBl21De3Uid161947 => 'GCA_000022665.2', # ASM2266v1
   EscherichiaColiBl21De3Uid161949 => 'GCA_000009565.2', # ASM956v1
   # Escherichia coli BL21 Gold DE3 pLysS AG
   EscherichiaColiBl21GoldDe3PlyssAgUid59245 => 'GCA_000023665.1', # ASM2366v1
   # Escherichia coli BW2952
   EscherichiaColiBw2952Uid59391 => 'GCA_000022345.1', # ASM2234v1
   EscherichiaColiBRel606Uid58803 => 'GCA_000017985.1', # ASM1798v1
   EscherichiaColiCft073Uid57915 => 'GCA_000007445.1', # ASM744v1
   EscherichiaColiDh1Uid161951 => 'GCA_000023365.1', # ASM2336v1
   EscherichiaColiDh1Uid162051 => 'GCA_000023365.1', # ASM2336v1
   EscherichiaColiCloneDI14Uid162049 => 'GCA_000233895.1', # ASM23389v1
   EscherichiaColiCloneDI2Uid162047 => 'GCA_000233875.1', # ASM23387v1
   EscherichiaColiE24377aUid58395 => 'GCA_000017745.1', # ASM1774v1
   EscherichiaColiEd1aUid59379 => 'GCA_000026305.1', # ASM2630v1
   EscherichiaColiEtecH10407Uid161993 => 'GCA_000210475.1', # ASM21047v1
   EscherichiaColiHsUid58393 => 'GCA_000017765.1', # ASM1776v1
   EscherichiaColiIai1Uid59377 => 'GCA_000026265.1', # ASM2626v1
   EscherichiaColiIai39Uid59381 => 'GCA_000026345.1', # ASM2634v1
   EscherichiaColiIhe3034Uid162007 => 'GCA_000025745.1', # ASM2574v1
   EscherichiaColiK12SubstrDh10bUid58979 => 'GCA_000019425.1', # ASM1942v1
   EscherichiaColiK12SubstrMg1655Uid57779 => 'GCA_000005845.1', # ASM584v1
   EscherichiaColiK12SubstrW3110Uid161931 => 'GCA_000010245.1', # ASM1024v1
   EscherichiaColiKo11flUid162099 => 'GCA_000147855.2', # EKO11
   EscherichiaColiKo11flUid52593 => 'GCA_000147855.2', # EKO11
   EscherichiaColiLf82Uid161965 => 'GCA_000284495.1', # ASM28449v1
   EscherichiaColiNa114Uid162139 => 'GCA_000214765.2', # ASM21476v2
   EscherichiaColiO103H212009Uid41013 => 'GCA_000010745.1', # ASM1074v1
   EscherichiaColiO104H42009el2050Uid175905 => 'GCA_000299255.1', # ASM29925v1
   EscherichiaColiO104H42009el2071Uid176128 => 'GCA_000299475.1', # ASM29947v1
   EscherichiaColiO104H42011c3493Uid176127 => 'GCA_000299455.1', # ASM29945v1
   EscherichiaColiO111H11128Uid41023 => 'GCA_000010765.1', # ASM1076v1
   EscherichiaColiO127H6E234869Uid59343 => 'GCA_000026545.1', # ASM2654v1
   EscherichiaColiO157H7Ec4115Uid59091 => 'GCA_000021125.1', # ASM2112v1
   EscherichiaColiO157H7Edl933Uid57831 => 'GCA_000006665.1', # ASM666v1
   EscherichiaColiO157H7SakaiUid57781 => 'GCA_000008865.1', # ASM886v1
   EscherichiaColiO157H7Tw14359Uid59235 => 'GCA_000022225.1', # ASM2222v1
   EscherichiaColiO26H1111368Uid41021 => 'GCA_000091005.1', # ASM9100v1
   EscherichiaColiO55H7Cb9615Uid46655 => 'GCA_000025165.1', # ASM2516v1
   EscherichiaColiO55H7Rm12579Uid162153 => 'GCA_000245515.1', # ASM24551v1
   EscherichiaColiO7K1Ce10Uid162115 => 'GCA_000227625.1', # ASM22762v1
   EscherichiaColiO83H1Nrg857cUid161987 => 'GCA_000183345.1', # ASM18334v1
   EscherichiaColiP12bUid162061 => 'GCA_000257275.1', # ASM25727v1
   EscherichiaColiS88Uid62979 => 'GCA_000026285.1', # ASM2628v1
   EscherichiaColiSe11Uid59425 => 'GCA_000010385.1', # ASM1038v1
   EscherichiaColiSe15Uid161939 => 'GCA_000010485.1', # ASM1048v1
   EscherichiaColiSms35Uid58919 => 'GCA_000019645.1', # ASM1964v1
   ShigellaBoydiiSb227Uid58215 => 'GCA_000012025.1', # ASM1202v1
   ShigellaBoydiiCdc308394Uid58415 => 'GCA_000020185.1', # ASM2018v1
   ShigellaDysenteriaeSd197Uid58213 => 'GCA_000012005.1', # ASM1200v1
   ShigellaFlexneri2002017Uid159233 => 'GCA_000022245.1', # ASM2224v1
   ShigellaFlexneri2a2457tUid57991 => 'GCA_000183785.2', # ASM18378v2
   ShigellaFlexneri2a301Uid62907 => 'GCA_000006925.2', # ASM692v2
   ShigellaFlexneri58401Uid58583 => 'GCA_000013585.1', # ASM1358v1
   ShigellaSonneiSs046Uid58217 => 'GCA_000092525.1', # ASM9252v1
   ShigellaSonnei53gUid84383 => 'GCA_000188795.2', # ASM18879v2
   EscherichiaColiUm146Uid162043 => 'GCA_000148605.1', # ASM14860v1
   EscherichiaColiUmn026Uid62981 => 'GCA_000026325.1', # ASM2632v1
   EscherichiaColiUmnk88Uid161991 => 'GCA_000212715.2', # ASM21271v2
   EscherichiaColiUti89Uid58541 => 'GCA_000013265.1', # ASM1326v1
   EscherichiaColiWUid162011 => 'GCA_000147755.2', # ASM14775v1
   EscherichiaColiWUid162101 => 'GCA_000147755.2', # ASM14775v1
   EscherichiaColiXuzhou21Uid163995 => 'GCA_000262125.1', # ASM26212v1
   #
   # http://hgwdev.cse.ucsc.edu/~jcarmstr/crocBrowserRC2/hub.txt
   #
   # American alligator
   allMis2 => 'GCA_000281125.1', # Couldn't find NCBI entry, mapped to same as allMis1 
   # Anc00 => '', # No public assembly
   # ..
   # Anc21 => '',
   # Melopsittacus undulatus (entry already exist)
   # melUnd1 => 'GCA_000238935.1', # Melopsittacus_undulatus_6.3
   # Ficedula albicollis
   ficAlb2 => 'GCA_000247815.2', # FicAlb1.5
   # Crocodile
   croPor2 => 'GCA_000768395.1', # Cpor_2.0
   # Gavialis gangeticus
   ghaGan1 => 'GCA_000775435.1', # ggan_v0.2
   # Chelonia mydas
   cheMyd1 => 'GCA_000344595.1', # CheMyd_1.0
   # Lizard (anoCar2, entry already exist)
   # Anas platyrynchos
   anaPla1 => 'GCA_000355885.1', # BGI_duck_1.0
   # Medium ground finch (geoFor1, entry already exist)
   # Ostrich
   strCam0 => 'GCA_000698965.1', # ASM69896v1
   # Painted turtle (chrPic1, entry already exist)
   # Amazona vittata
   amaVit1 => 'GCA_000332375.1', # AV1 
   # Falco peregrinus
   falPer1 => 'GCA_000337955.1', # F_peregrinus_v1.0
   # Columba livia
   colLiv1 => 'GCA_000337935.1', # Cliv_1.0
   # Falco cherrug
   falChe1 => 'GCA_000337975.1', # F_cherrug_v1.0
   # Ara macao
   araMac1 => 'GCA_000400695.1', # SMACv1.1
   # Soft cell turtle
   pelSin1 => 'GCA_000230535.1', # PelSin_1.0
   # Spiny soft cell turtle
   apaSpi1 => 'GCA_000385615.1', # ASM38561v1
   # Tibetan ground jay
   pseHum1 => 'GCA_000331425.1', # PseHum1.0
   # Turkey (melGal1 , entry already present)
   # White throated sparrow
   zonAlb1 => 'GCA_000385455.1', # Zonotrichia_albicollis-1.0.1
   # Taeniopygia guttata
   taeGut2 => 'GCA_000151805.2', # Taeniopygia_guttata-3.2.4 (same as taeGut1)
   #
   # http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt
   #
   # Drosophila simulans w501
   'Dsim-w501' => 'GCA_000754195.2', # ASM75419v2
  };

#
# Add species/assembly info
#
sub _add_genome_info {
  my ($self, $genome, $doc) = @_;
  defined $genome and defined $doc or
    die "Undefined genome and/or doc arguments";

  #
  # Map the (UCSC) assembly synonym to NCBI assembly entry,
  # i.e. an entry in the genome collection db
  #
  my $assembly_syn = $genome->assembly;
  my $assembly_id = $synonym2assembly->{$assembly_syn};

  #
  # TODO
  #
  # If the assembly id is not found, it means the assembly
  # is not supported by the UCSC genome browser.
  # The trackhub provider must be able to provide additional fields,
  # e.g. the scientific name of the organism.
  # The assembly should be indicated in the html page
  # provided by htmlPath attribute, but how do we parse the page?
  #
  # Option:
  #   Select an assembly from the organism name. If there's more than 1, 
  #   select the most up-to-date.
  #
  # At the moment, just throw an exception.
  # When submitters discover the error, we can find out which assembly
  # id they mean and update the mappings accordingly
  #
  # unless ($assembly_id) {    
  # } 
  die "Unable to find an NCBI assembly id from $assembly_syn"
    unless defined $assembly_id;

  #
  # Get species (tax id, scientific name, common name)
  # and assembly info from the assembly set table in the GC database
  #
  my $gc_assembly_set = $self->gc_assembly_set;
  my $as = $gc_assembly_set->find($assembly_id);
  die "Unable to find GC assembly set entry for $assembly_id"
    unless $as;
  
  my ($tax_id, $scientific_name, $common_name) = 
    ($as->tax_id, $as->scientific_name, $as->common_name);
  # TODO: taxid and scientific name are mandatory

  $doc->{species}{tax_id} = $tax_id if $tax_id;
  $doc->{species}{scientific_name} = $scientific_name if $scientific_name;
  $doc->{species}{common_name} = $common_name if $common_name;

  $doc->{assembly}{accession} = $assembly_id;
  $doc->{assembly}{name} = $as->name;
  $doc->{assembly}{long_name} = $as->long_name if $as->long_name; # sometimes not defined
  $doc->{assembly}{synonyms} = $assembly_syn;

  return;
}

1;
