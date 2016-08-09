=head1 LICENSE

Copyright [2015-2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

#
# A class to represent a translator from UCSC-style trackdb
# documents to the corresponding JSON specification
#
package Registry::TrackHub::Translator;

use strict;
use warnings;

use JSON;
# use Registry::GenomeAssembly::Schema;
use Registry;
use Registry::Utils;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Registry::TrackHub;
use Registry::TrackHub::Tree;
use Registry::TrackHub::Parser;

use Bio::EnsEMBL::Utils::MetaData::DBSQL::GenomeInfoAdaptor;

use vars qw($AUTOLOAD $ucscdb2insdc);

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;

  return $self->{$attr};
}

my %format_lookup = (
		     'bed'    => 'BED',
		     'bb'     => 'BigBed',
		     'bigBed' => 'BigBed',
		     'bw'     => 'BigWig',
		     'bigWig' => 'BigWig',
		     'bam'    => 'BAM',
		     'gz'     => 'VCFTabix',
		     'cram'   => 'CRAM'
		    );

sub new {
  my ($class, %args) = @_;
  
  defined $args{version} or die "Undefined version";

  my $self = \%args;

  # # TODO: Load the GCAssemblySet from the catalyst model which reads
  # #       the connection parameters from the configuration file
  # my $gcschema = 
  #   Registry::GenomeAssembly::Schema->connect("DBI:Oracle:host=ora-vm5-003.ebi.ac.uk;sid=ETAPRO;port=1571", 
  # 					      'gc_reader', 
  # 					      'reader', 
  # 					      { 'RaiseError' => 1, 'PrintError' => 0 });
  # $self->{gc_assembly_set} = $gcschema->resultset('GCAssemblySet');

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

  my $trackhub = Registry::TrackHub->new(url => $url, permissive => $self->permissive);
  
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
		 name       => $trackhub->hub,
		 shortLabel => $trackhub->shortLabel,
		 longLabel  => $trackhub->longLabel,
		 url        => $trackhub->url,
		 assembly   => $genome->twoBitPath?1:0 # detect if it is an assembly hub
		},
     # add the original trackDb file as the source
     source => { 
		url => $genome->trackDb->[0],
		checksum => Registry::Utils::checksum_compute($genome->trackDb->[0])
	       }
    };

  # add species/assembly information
  $self->_add_genome_info($genome, $doc);

  # add links to genome browsers
  $self->_add_genome_browser_links($genome, $doc);

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
  
  # collect trackDB stats, i.e. # tracks, # tracks linked to data, file types
  $doc->{status} =
    { 
     tracks  => {
		 total => 0,
		 with_data => {
			       total => 0,
			       total_ko => 0
			      }
		},
     message => 'Unchecked',
     last_update => ''
    };
  $doc->{file_type} = {};

  $self->_collect_track_info($doc->{configuration}, $doc->{status}, $doc->{file_type});
  
  return to_json($doc, { pretty => 1 });
}


sub _make_configuration_object_1_0 {
  my ($self, $node) = @_;
  defined $node or die "Undefined args";
  
  # add the configuration attributes as they are specified
  my $node_conf = {};
  # map { $node_conf->{$_} = $node->data->{$_} } keys %{$node->data};
  map { $node->data->{$_} and $node_conf->{$_} = $node->data->{$_} } keys %{$node->data};
  # delete $node_conf->{track};

  # now add the configuration of the children, if any
  for my $child (@{$node->child_nodes}) {
    my $child_conf = $self->_make_configuration_object_1_0($child);
    $node_conf->{members}{$child_conf->{track}} = $child_conf;
  }

  return $node_conf;
}

sub _collect_track_info {
  my ($self, $hash, $status, $file_type) = @_;
  foreach my $track (keys %{$hash}) { # key is track name
    ++$status->{tracks}{total};

    if (ref $hash->{$track} eq 'HASH') {
      foreach my $attr (keys %{$hash->{$track}}) {
	next unless $attr =~ /bigdataurl/i or $attr eq 'members';
	if ($attr eq 'members') {
	  $self->_collect_track_info($hash->{$track}{$attr}, $status, $file_type) if ref $hash->{$track}{$attr} eq 'HASH';
	} else {
	  ++$status->{tracks}{with_data}{total};

	  # determine type
	  my $url = $hash->{$track}{$attr};
	  my @path = split(/\./, $url);
	  my $index = -1;
	  # # handle compressed formats
	  # $index = -2 if $path[-1] eq 'gz';
	  $file_type->{$format_lookup{$path[$index]}}++;
	}

      }
    }
  } 
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
$ucscdb2insdc = 
  {
   #
   # These mappings have been derived from the list of UCSC genome releases at:
   # https://genome.ucsc.edu/FAQ/FAQreleases.html#release1
   #
   # Mammals
   #
   # human
   hg38 => 'GCA_000001405.15', # 'GRCh38', E
   hg19 => 'GCA_000001405.1', # 'GRCh37',
   hg18 => 'GCF_000001405.12', #'NCBI36',
   hg17 => 'GCF_000001405.11', # 'NCBI35',
   hg16 => 'GCF_000001405.10', # 'NCBI34',
   # alpaca
   vicpac2 => 'GCA_000164845.2', # 'Vicugna_pacos-2.0.1' 
   vicpac1 => 'GCA_000164845.1', # 'VicPac1.0', # no NCBI syn 
   # armadillo
   dasnov3 => 'GCA_000208655.2', # 'Dasnov3.0',
   # bushbaby
   otogar3 => 'GCA_000181295.3', # 'OtoGar3',
   # baboon
   # papham1 => 'Pham_1.0', # not found on NCBI
   papanu2 => 'GCA_000264685.1', # 'Panu_2.0',
   # cat
   felcat5 => 'GCA_000181335.2', # 'Felis_catus-6.2',
   felcat4 => 'GCA_000003115.1', # 'catChrV17e',
   # felcat3 => '', # no name found
   # chimp
   pantro4 => 'GCA_000001515.4', # 'Pan_troglodytes-2.1.4',
   pantro3 => 'GCA_000001515.3', # 'Pan_troglodytes-2.1.3',
   pantro2 => 'GCF_000001515.3', # 'Pan_troglodytes-2.1', # no syn on NCBI
   # pantro1 => '', # not found
   # chinese hamster
   crigri1 => 'GCA_000419365.1', # 'C_griseus_v1.0', # no syn on NCBI
   # cow
   bostau8 => 'GCA_000003055.5', # 'Bos_taurus_UMD_3.1.1', # no syn on NCBI
   bostau7 => 'GCA_000003205.4', # 'Btau_4.6.1',
   bostau6 => 'GCA_000003055.3', # 'Bos_taurus_UMD_3.1', # no synonym reported by NCBI and E, E
   bostau4 => 'GCF_000003205.2', # 'Btau_4.0',
   bostau3 => 'GCF_000003205.1', # 'Btau_3.1', # no synonym reported by NCBI
   # bostau2 => 'Btau_2.0', # no Btau_2.0 entry in NCBI
   # bostau1 => 'Btau_1.0', # no Btau_1.0 entry in NCBI
   # dog
   canfam3 => 'GCA_000002285.2', # 'CanFam3.1',
   canfam2 => 'GCA_000002285.1', # 'CanFam2.0',
   # canfam1 => '', # not found on NCBI
   # dolphin
   turtru2 => 'GCA_000151865.2', # 'Ttru_1.4'
   # elephant
   loxafr3 => 'GCA_000001905.1', # 'Loxafr3.0',
   # ferret
   musfur1 => 'GCA_000215625.1', # 'MusPutFur1.0',
   # gibbon
   nomleu3 => 'GCA_000146795.3', # 'Nleu_3.0',
   nomleu2 => 'GCA_000146795.2', # 'Nleu1.1',
   nomleu1 => 'GCA_000146795.1', # 'Nleu1.0', 
   # gorilla
   gorgor3 => 'GCA_000151905.1', # 'gorGor3.1',
   # guinea pig
   cavpor3 => 'GCA_000151735.1', # 'Cavpor3.0',
   # hedgehog
   erieur2 => 'GCA_000296755.1', # 'EriEur2.0', # no syn on NCBI
   erieur1 => 'GCA_000181395.1', # ASM18139v1 (no Draft_v1 entry in NCBI)
   # horse
   equcab2 => 'GCA_000002305.1', # 'EquCab2.0',
   # equcab1 => 'EquCab1.0', # no EquCab1.0 entry on NCBI
   # kangaroo rat (Dipodomys merriami not found, refer to Dipodomys ordii instead
   dipord1 => 'GCA_000151885.1', # DipOrd1.0
   # manatee
   triman1 => 'GCA_000243295.1', # 'TriManLat1.0',
   # marmoset
   caljac3 => 'GCA_000004665.1', # 'Callithrix_jacchus-v3.2',
   # caljac1 => 'Callithrix_jacchus-v2.0.2', # no Callithrix_jacchus-v2.0.2 entry on NCBI
   # megabat
   ptevam1 => 'GCA_000151845.1', # 'Ptevap1.0',
   # microbat
   myoluc2 => 'GCA_000147115.1', # 'Myoluc2.0',
   # minke whale
   balacu1 => 'GCA_000493695.1', # 'BalAcu1.0', # no synonym in NCBI
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
   micmur1 => 'GCA_000165445.1', # 'ASM16544v1', # no MicMur1.0 entry on NCBI
   # naked mole rat
   hetgla2 => 'GCA_000247695.1', # 'HetGla_female_1.0',
   hetgla1 => 'GCA_000230445.1', # 'HetGla_1.0', # no synonym on NCBI
   # opossum
   mondom5 => 'GCF_000002295.2', # 'MonDom5',
   # mondom4 => 'MonDom4', # no MonDom4 entry
   # mondom1 => 'MonDom1', # no MonDom1 entry
   # orangutan
   # ponabe2 => 'Pongo_albelii-2.0.2', # NCBI reports instead
   ponabe2 => 'GCA_000001545.3', # 'P_pygmaeus_2.0.2',
   # panda
   ailmel1 => 'GCA_000004335.1', # 'AilMel_1.0',
   # pig
   susscr3 => 'GCA_000003025.4', # 'Sscrofa10.2',
   susscr2 => 'GCA_000003025.2', # 'Sscrofa9.2', # no syn on NCBI
   # pika
   ochpri3 => 'GCA_000292845.1', # 'OchPri3.0', # no syn on NCBI
   ochpri2 => 'GCA_000164825.1', # 'OchPri2'
   ochpri2 => 'GCA_000164825.1', # 'ASM16482v1', 
   # platypus
   ornana1 => 'GCF_000002275.2', # 'Ornithorhynchus_anatinus-5.0.1', # no syn on NCBI
   # rabbit
   orycun2 => 'GCA_000003625.1', # 'OryCun2.0',
   # rat
   rn6 => 'GCA_000001895.4', # 'Rnor_6.0',
   rn5 => 'GCA_000001895.3', # 'Rnor_5.0',
   rn4 => 'GCF_000001895.3', # 'RGSC_v3.4', # no syn on NCBI
   # rn3 => 'RGSC_v3.1', # not found
   # rn2 => 'RGSC_v2.1', # not found
   # rn1 => 'RGSC_v1.0', # not found
   # rhesus (Macaca mulatta)
   rhemac3 => 'GCA_000230795.1', # 'CR_1.0',
   rhemac2 => 'GCA_000002255.1', # 'Mmul_051212',
   # rhemac1 => 'Mmul_0.1', # not found
   # rock hyrax
   procap1 => 'GCA_000152225.1', # 'Procap1.0',
   # sheep
   oviari3 => 'GCA_000298735.1', # 'Oar_v3.1',
   # oviari1 => '', # not found
   # shrew
   sorara2 => 'GCA_000181275.2', # 'SorAra2.0',
   sorara1 => 'GCA_000181275.1', # ASM18127v1, 'SorAra1.0' not found
   # sloth
   chohof1 => 'GCA_000164785.1', # 'ChoHof1.0',
   # squirrel
   spetri2 => 'GCA_000236235.1', # 'SpeTri2.0',
   # squirrel monkey
   saibol1 => 'GCA_000235385.1', # 'SaiBol1.0',
   # tarsier
   tarsyr1 => 'GCA_000164805.1', # 'Tarsyr1.0',
   # tasmanian devil
   sarhar1 => 'GCA_000189315.1', # 'Devil_ref v7.0',
   # tenrec
   echtel2 => 'GCA_000313985.1', # 'EchTel2.0',
   # echtel1 => 'echTel1', # not found
   # tree shrew
   # tupbel1 => 'Tupbel1.0', # no Tupebel1.0 found
   # wallaby
   maceug2 => 'GCA_000004035.1', # 'Meug_1.1', # no syn on NCBI
   # white rhinoceros
   cersim1 => 'GCA_000283155.1', # 'CerSimSim1.0',
   #
   # Vertebrates
   #
   # american alligator
   allmis1 => 'GCA_000281125.1', # 'allMis0.2',
   # atlantic cod
   gadmor1 => 'GCA_000231765.1', # 'GadMor_May2010',
   # budgerigar
   melund1 => 'GCA_000238935.1', # 'Melopsittacus_undulatus_6.3',
   # chicken
   galgal4 => 'GCA_000002315.2', # 'Gallus_gallus-4.0',
   galgal3 => 'GCA_000002315.1', # 'Gallus_gallus-2.1',
   # galgal2 => 'Gallus-gallus-1.0', # no Gallus-gallus-1.0 on NCBI
   # coelacanth
   latcha1 => 'GCA_000225785.1', # 'LatCha1',
   # elephant shark
   calmil1 => 'GCA_000165045.2', # 'Callorhinchus_milli-6.1.3', # no syn on NCBI
   # fugu
   fr3 => 'GCA_000180615.2', # 'FUGU5',
   # fr2 => '', # not found
   # fr1 => '', # not found
   # lamprey
   petmar2 => 'GCA_000148955.1', # 'Petromyzon_marinus-7.0',
   # petmar1 => '', # not found
   # lizard (Anolis carolinensis)
   anocar2 => 'GCA_000090745.1', # 'AnoCar2.0', E
   # anocar1 => 'AnoCar1', # not found
   # medaka
   # orylat2 => '', # not found
   # medium ground finch
   geofor1 => 'GCA_000277835.1', # 'GeoFor_1.0', # no syn on NCBI
   # nile tilapia
   orenil2 => 'GCA_000188235.2', # 'Orenil1.1',
   # painted turtle
   chrpic1 => 'GCA_000241765.1', # 'Chrysemys_picta_bellii-3.0.1',
   # stickleback
   gasacu1 => 'GCA_000180675.1', # ASM18067v1
   # tetraodon
   # tetnig2 => '',
   tetnig1 => 'GCA_000180735.1', # 'ASM18073v1',
   # turkey
   melgal1 => 'GCA_000146605.2', # 'Turkey_2.01',
   # xenopus tropicalis
   xentro3 => 'GCA_000004195.1', # 'v4.2',
   # xentro2 => 'v4.1', # not found
   # xentro2 => 'v3.0', # not found
   # zebra finch
   # taegut2 => '', # not found
   taegut1 => 'GCA_000151805.2', # 'Taeniopygia_guttata-3.2.4',
   # zebrafish
   danrer10 => 'GCA_000002035.3', # 'GRCz10', no syn on on NCBI
   danrer7 => 'GCA_000002035.2', # 'Zv9'
   danrer6 => 'GCA_000002035.1', # 'Zv8', no syn on on NCBI
   danrer5 => 'GCF_000002035.1', # 'Zv7',
   # danrer4 => 'Zv6', # not found on NCBI
   # danrer3 => 'Zv5', # not found on NCBI
   # danrer2 => 'Zv4', # not found on NCBI
   # danrer1 => 'Zv3', # not found on NCBI
   #
   # Deuterostomes
   #
   # C. intestinalis
   ci2 => 'GCA_000224145.1', # derived from ensembl meta
   ci1 => 'GCA_000183065.1', # 'v1.0',
   # lancelet, not found
   # braflo1 => '',
   # Strongylocentrotus purpuratus
   strpur2 => 'GCF_000002235.2', # 'Spur_v2.1',
   strpur1 => 'GCF_000002235.1', # 'Spur_0.5', # no syn on NCBI
   #
   # Insects
   #
   # Apis mellifera
   apimel2 => 'GCF_000002195.1', # 'Amel_2.0', # no syn on NCBI
   # apimel1 => 'v.Amel_1.2', # no v.Amel_1.2 entry on NCBI
   # Anopheles gambiae
   # anogam1 => 'v.MOZ2', # not found
   # Drosophila ananassae
   droana3 => 'GCA_000005115.1', # 'dana_caf1', # no droAna3 UCSC syn
   # droana2 => '', # not found
   # droana1 => '', # not found
   # Drosophila erecta
   droere2 => 'GCA_000005135.1', # 'dere_caf1', # no droEre2 UCSC syn
   # droere1 => '', # not found
   # Drosophila grimshawi
   drogri2 => 'GCA_000005155.1', # 'dgri_caf1', # no droGri2 UCSC syn
   # drogri1 => '', # not found
   # Drosophila melanogaster
   dm6 => 'GCA_000001215.4', # 'Release 6 plus ISO1 MT',
   dm3 => 'GCA_000001215.2', # 'Release 5',
   # dm2 => 'Release 4', # no Release 4 
   # dm1 => 'Release 3', # no Release 3
   # Drosophila mojavensis
   dromoj3 => 'GCA_000005175.1', # 'dmoj_caf1', # no droMoj3 UCSC syn
   # dromoj2 => '', # not found
   # dromoj1 => '', # not found
   # Drosophila persimilis
   droper1 => 'GCA_000005195.1', # 'dper_caf1',
   # Drosophila pseudoobscura, not found
   # dp3 => '',
   # dp2 => '',
   # Drosophila sechellia
   drosec1 => 'GCA_000005215.1', # 'dsec_caf1',
   # Drosophila simulans
   drosim1 => 'GCA_000259055.1', # 'dsim_caf1', # not sure, several v1 for different strains on NCBI
   # Drosophila virilis
   drovir3 => 'GCA_000005245.1', # 'dvir_caf1', # no droVir3 UCSC syn
   # drovir2 => '', # not found
   # drovir1 => '', # not found
   # Drosophila yakuba
   # droyak2 => '', # not found
   # droyak1 => '', # not found
   #
   # Nematodes
   #
   # Caenorhabditis brenneri
   caepb2 => 'GCA_000143925.1', # 'C_brenneri-6.0.1', # not sure (not 2008)
   # caepb1 => '', # not found
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
   # caejap1 => '', # not found
   # Caenorhabditis remanei
   # caerem3 => '', # not found
   # caerem2 => '',
   # Pristionchus pacificus
   # pripac1 => '', # not found
   #
   # Other
   #
   # sea hare
   aplcal1 => 'GCA_000002075.1', # 'Aplcal2.0',
   # Yeast
   saccer3 => 'GCA_000146045.2', # 'R64-1-1',
   # saccer2 => '', # not found
   # saccer1 => '', # not found
   # ebola virus
   # ebovir3 => '', # not found
   #
   # And the following mappings have been derived by looking
   # the UCSC synonyms for the assemblies in the public hubs at:
   # http://genome.ucsc.edu/cgi-bin/hgHubConnect
   #
   # http://smithlab.usc.edu/trackdata/methylation/hub.txt
   #
   # Arabidopsis thaliana
   # tair10 => 'GCA_000001735.1', # TAIR10
   # tair9  => 'GCA_000001735.1', # TAIR9
   #
   # http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt
   #
   # Arabidopsis thaliana
   aratha1 => 'GCA_000001735.1', # TAIR10
   # Ricinus communis
   riccom1 => 'GCA_000151685.2', # JCVI_RCG_1.1
   # brassica rapa
   brarap1 => 'GCA_000309985.1', # Brapa_1.0
   #
   # http://genome-test.cse.ucsc.edu/~nknguyen/ecoli/publicHubs/pangenome/hub.txt
   # http://genome-test.cse.ucsc.edu/~nknguyen/ecoli/publicHubs/pangenomeWithDups/hub.txt
   #
   # Escherichia coli 042
   escherichiaColi042Uid161985 => 'GCA_000027125.1', # ASM2712v1
   # Escherichia coli 536
   escherichiaColi536Uid58531 => 'GCA_000013305.1', # ASM1330v1
   # Escherichia coli 55989
   escherichiaColi55989Uid59383 => 'GCA_000026245.1', # ASM2624v1
   # Escherichia coli ABU 83972
   escherichiaColiAbu83972Uid161975 => 'GCA_000148365.1', # ASM14836v1
   # Escherichia coli APEC O1
   escherichiaColiApecO1Uid58623 => 'GCA_000014845.1', # ASM1484v1
   # Escherichia coli ATCC 8739
   escherichiaColiAtcc8739Uid58783 => 'GCA_000019385.1', # ASM1938v1 
   # Escherichia coli BL21 DE3
   escherichiaColiBl21De3Uid161947 => 'GCA_000022665.2', # ASM2266v1
   escherichiaColiBl21De3Uid161949 => 'GCA_000009565.2', # ASM956v1
   # Escherichia coli BL21 Gold DE3 pLysS AG
   escherichiaColiBl21GoldDe3PlyssAgUid59245 => 'GCA_000023665.1', # ASM2366v1
   # Escherichia coli BW2952
   escherichiaColiBw2952Uid59391 => 'GCA_000022345.1', # ASM2234v1
   escherichiaColiBRel606Uid58803 => 'GCA_000017985.1', # ASM1798v1
   escherichiaColiCft073Uid57915 => 'GCA_000007445.1', # ASM744v1
   escherichiaColiDh1Uid161951 => 'GCA_000023365.1', # ASM2336v1
   escherichiaColiDh1Uid162051 => 'GCA_000023365.1', # ASM2336v1
   escherichiaColiCloneDI14Uid162049 => 'GCA_000233895.1', # ASM23389v1
   escherichiaColiCloneDI2Uid162047 => 'GCA_000233875.1', # ASM23387v1
   escherichiaColiE24377aUid58395 => 'GCA_000017745.1', # ASM1774v1
   escherichiaColiEd1aUid59379 => 'GCA_000026305.1', # ASM2630v1
   escherichiaColiEtecH10407Uid161993 => 'GCA_000210475.1', # ASM21047v1
   escherichiaColiHsUid58393 => 'GCA_000017765.1', # ASM1776v1
   escherichiaColiIai1Uid59377 => 'GCA_000026265.1', # ASM2626v1
   escherichiaColiIai39Uid59381 => 'GCA_000026345.1', # ASM2634v1
   escherichiaColiIhe3034Uid162007 => 'GCA_000025745.1', # ASM2574v1
   escherichiaColiK12SubstrDh10bUid58979 => 'GCA_000019425.1', # ASM1942v1
   escherichiaColiK12SubstrMg1655Uid57779 => 'GCA_000005845.1', # ASM584v1
   escherichiaColiK12SubstrW3110Uid161931 => 'GCA_000010245.1', # ASM1024v1
   escherichiaColiKo11flUid162099 => 'GCA_000147855.2', # EKO11
   escherichiaColiKo11flUid52593 => 'GCA_000147855.2', # EKO11
   escherichiaColiLf82Uid161965 => 'GCA_000284495.1', # ASM28449v1
   escherichiaColiNa114Uid162139 => 'GCA_000214765.2', # ASM21476v2
   escherichiaColiO103H212009Uid41013 => 'GCA_000010745.1', # ASM1074v1
   escherichiaColiO104H42009el2050Uid175905 => 'GCA_000299255.1', # ASM29925v1
   escherichiaColiO104H42009el2071Uid176128 => 'GCA_000299475.1', # ASM29947v1
   escherichiaColiO104H42011c3493Uid176127 => 'GCA_000299455.1', # ASM29945v1
   escherichiaColiO111H11128Uid41023 => 'GCA_000010765.1', # ASM1076v1
   escherichiaColiO127H6E234869Uid59343 => 'GCA_000026545.1', # ASM2654v1
   escherichiaColiO157H7Ec4115Uid59091 => 'GCA_000021125.1', # ASM2112v1
   escherichiaColiO157H7Edl933Uid57831 => 'GCA_000006665.1', # ASM666v1
   escherichiaColiO157H7SakaiUid57781 => 'GCA_000008865.1', # ASM886v1
   escherichiaColiO157H7Tw14359Uid59235 => 'GCA_000022225.1', # ASM2222v1
   escherichiaColiO26H1111368Uid41021 => 'GCA_000091005.1', # ASM9100v1
   escherichiaColiO55H7Cb9615Uid46655 => 'GCA_000025165.1', # ASM2516v1
   escherichiaColiO55H7Rm12579Uid162153 => 'GCA_000245515.1', # ASM24551v1
   escherichiaColiO7K1Ce10Uid162115 => 'GCA_000227625.1', # ASM22762v1
   escherichiaColiO83H1Nrg857cUid161987 => 'GCA_000183345.1', # ASM18334v1
   escherichiaColiP12bUid162061 => 'GCA_000257275.1', # ASM25727v1
   escherichiaColiS88Uid62979 => 'GCA_000026285.1', # ASM2628v1
   escherichiaColiSe11Uid59425 => 'GCA_000010385.1', # ASM1038v1
   escherichiaColiSe15Uid161939 => 'GCA_000010485.1', # ASM1048v1
   escherichiaColiSms35Uid58919 => 'GCA_000019645.1', # ASM1964v1
   shigellaBoydiiSb227Uid58215 => 'GCA_000012025.1', # ASM1202v1
   shigellaBoydiiCdc308394Uid58415 => 'GCA_000020185.1', # ASM2018v1
   shigellaDysenteriaeSd197Uid58213 => 'GCA_000012005.1', # ASM1200v1
   shigellaFlexneri2002017Uid159233 => 'GCA_000022245.1', # ASM2224v1
   shigellaFlexneri2a2457tUid57991 => 'GCA_000183785.2', # ASM18378v2
   shigellaFlexneri2a301Uid62907 => 'GCA_000006925.2', # ASM692v2
   shigellaFlexneri58401Uid58583 => 'GCA_000013585.1', # ASM1358v1
   shigellaSonneiSs046Uid58217 => 'GCA_000092525.1', # ASM9252v1
   shigellaSonnei53gUid84383 => 'GCA_000188795.2', # ASM18879v2
   escherichiaColiUm146Uid162043 => 'GCA_000148605.1', # ASM14860v1
   escherichiaColiUmn026Uid62981 => 'GCA_000026325.1', # ASM2632v1
   escherichiaColiUmnk88Uid161991 => 'GCA_000212715.2', # ASM21271v2
   escherichiaColiUti89Uid58541 => 'GCA_000013265.1', # ASM1326v1
   escherichiaColiWUid162011 => 'GCA_000147755.2', # ASM14775v1
   escherichiaColiWUid162101 => 'GCA_000147755.2', # ASM14775v1
   escherichiaColiXuzhou21Uid163995 => 'GCA_000262125.1', # ASM26212v1
   #
   # http://hgwdev.cse.ucsc.edu/~jcarmstr/crocBrowserRC2/hub.txt
   #
   # American alligator
   allmis2 => 'GCA_000281125.1', # Couldn't find NCBI entry, mapped to same as allMis1 
   # anc00 => '', # No public assembly
   # ..
   # anc21 => '',
   # Melopsittacus undulatus (entry already exist)
   # melund1 => 'GCA_000238935.1', # Melopsittacus_undulatus_6.3
   # Ficedula albicollis
   ficalb2 => 'GCA_000247815.2', # FicAlb1.5
   # Crocodile
   cropor2 => 'GCA_000768395.1', # Cpor_2.0
   # Gavialis gangeticus
   ghagan1 => 'GCA_000775435.1', # ggan_v0.2
   # Chelonia mydas
   chemyd1 => 'GCA_000344595.1', # CheMyd_1.0
   # Lizard (anoCar2, entry already exist)
   # Anas platyrynchos
   anapla1 => 'GCA_000355885.1', # BGI_duck_1.0
   # Medium ground finch (geoFor1, entry already exist)
   # Ostrich
   strcam0 => 'GCA_000698965.1', # ASM69896v1
   # Painted turtle (chrPic1, entry already exist)
   # Amazona vittata
   amavit1 => 'GCA_000332375.1', # AV1 
   # Falco peregrinus
   falper1 => 'GCA_000337955.1', # F_peregrinus_v1.0
   # Columba livia
   colliv1 => 'GCA_000337935.1', # Cliv_1.0
   # Falco cherrug
   falche1 => 'GCA_000337975.1', # F_cherrug_v1.0
   # Ara macao
   aramac1 => 'GCA_000400695.1', # SMACv1.1
   # Soft cell turtle
   pelsin1 => 'GCA_000230535.1', # PelSin_1.0
   # Spiny soft cell turtle
   apaspi1 => 'GCA_000385615.1', # ASM38561v1
   # Tibetan ground jay
   psehum1 => 'GCA_000331425.1', # PseHum1.0
   # Turkey (melGal1 , entry already present)
   # White throated sparrow
   zonalb1 => 'GCA_000385455.1', # Zonotrichia_albicollis-1.0.1
   # Taeniopygia guttata
   taegut2 => 'GCA_000151805.2', # Taeniopygia_guttata-3.2.4 (same as taeGut1)
   #
   # http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt
   #
   # Drosophila simulans w501
   'dsim-w501' => 'GCA_000754195.2', # ASM75419v2
  };

#
# From assembly synonyms to URLs that load the data hub into ensembl
#
# UCSC
#
# http://genome-euro.ucsc.edu/cgi-bin/hgHubConnect?hubUrl=http%3A%2F%2Fngs.sanger.ac.uk%2Fproduction%2Fensembl%2Fregulation%2Fhub.txt&db=hg38&hgHub_do_redirect=on&hgHubConnect.remakeTrackHub=on
# http://genome-euro.ucsc.edu/cgi-bin/hgHubConnect?hubUrl=http%3A%2F%2Fftp.ebi.ac.uk%2Fpub%2Fdatabases%2Fblueprint%2Freleases%2Fcurrent_release%2Fhomo_sapiens%2Fhub%2Fhub.txt&db=hg38&hgHub_do_redirect=on&hgHubConnect.remakeTrackHub=on&hgsid=209865411_yg74GaQ2WyJfv1cRBADYVmA38euZ
#
# See also http://genome.ucsc.edu/goldenPath/help/hgTrackHubHelp.html#Session
#
# EnsEMBL
#
# map the assembly synonym to the current (grch37 in case of human and hg19) or an archive web site,
# based on the list here:
# http://www.ensembl.org/info/website/archives/assembly.html
#
# EnsEMBL supported assemblies since v76 (proper track hub support)
#
# Note: info, e.g. accession can derived from meta tables
#
# species, Assembly name, Accession, UCSC name
#
# Alpaca, VicPac1.0, GCA_000164845.1, vicPac1
# Amazon molly, Poecilia_formosa-5.1.2, GCA_000485575.1, none
# Anole lizard, Anocar2.0, GCA_000090745.2, anoCar2 
# Armadillo, Dasnov3.0, GCA_000208655.2, dasNov3
# Bushbaby, OtoGar3, GCA_000181295.3, otoGar3
# Ciona intestinalis, KH, GCA_000224145.2, none
# Ciona savignyi, CSAV 2.0, ?, none
# Caenorhabditis elegans, WBcel215, GCA_000002985.2, ce10
# Cat, Felis_catus_6.2, GCA_000181335.2, felCat5
# Cave fish, Astyanax_mexicanus-1.0.2, GCA_000372685.1, none
# Chicken, Gallus_gallus-4.0, GCA_000002315.2, galGal4
# Chimpanzee, Pan_troglodytes-2.1.4 (CHIMP2.1.4), GCA_000001515.4, panTro4
# Chinese softshell turtle, PelSin_1.0, GCA_000230535.1, pelSin1
# Cod, GadMor_May2010, GCA_000231765.1, gadMor1
# Coelacanth, LatCha1, GCA_000225785.1, latCha1
# Cow, Bos_taurus_UMD_3.1 (UMD3.1), GCA_000003055.3, bosTau6
# Dog, CanFam3.1, GCA_000002285.2, canFam3
# Dolphin, turTru1, ?, ?
# Duck, BGI_duck_1.0, GCA_000355885.1, none (anaPla1 in http://hgwdev.cse.ucsc.edu/~jcarmstr/crocBrowserRC2/hub.txt but assembly hub)
# Elephant, Loxafr3.0, GCA_000001905.1, loxAfr3
# Ferret, MusPutFur1.0, GCA_000215625.1, musFur1
# Flycatcher, FicAlb_1.4, GCA_000247815.1, none
# Fruitfly, Release 6 plus ISO1 MT (BDGP6), GCA_000001215.4, dm6
# Fruitfly, Release 5 (BDGP 5), GCA_000001215.2, dm3
# Fugu, FUGU 4.0, ?, fr2
# Gibbon, Nleu1.0, GCA_000146795.1, nomLeu1
# Gorilla, gorGor3.1, GCA_000151905.1, gorGor3
# Guinea Pig, Cavpor3.0 (cavPor3), GCA_000151735.1, cavPor3
# Hedgehog, ASM18139v1 (eriEur1), GCA_000181395.1, eriEur1
# Horse, EquCab2.0 (Equ Cab 2), GCA_000002305.1, equCab2
# Human, GRCh38, GCA_000001405.15, hg38
# Human, GRCh37, GCA_000001405.1, hg19
# Hyrax, Procap1.0 (proCap1), GCA_000152225.1, proCap1
# Kangaroo rat, DipOrd1.0 (dipOrd1), GCA_000151885.1, dipOrd1
# Lamprey, Petromyzon_marinus-7.0 (Pmarinus_7.0), GCA_000148955.1, petMar2
# Lesser hedgehog tenrec, EchTel2.0, GCA_000313985.1, echTel2
# Macaque, CR_1.0 (MMUL 1.0), GCA_000230795.1, rheMac3
# Marmoset, C_jacchus3.2.1, ?, ? # Callithrix_jacchus-v3.2, GCA_000004665.1, calJac3 instead?
# Medaka, ASM31367v1 (HdrR), GCA_000313675.1, none
# Megabat, pteVam1 (Ptevap1.0), GCA_000151845.1, pteVam1
# Microbat, Myoluc2.0, GCA_000147115.1, myoLuc2
# Mouse, GRCm38, GCA_000001635.2, mm10
# Mouse lemur, ASM16544v1 (micMur1), GCA_000165445.1, micMur1
# Olive baboon, PapAnu2.0 (Panu_2.0), GCA_000264685.1, papAnu2
# Opossum, monDom5 (MonDom5), GCF_000002295.2, monDom5
# Orangutan, PPYG2, ?, ?
# Panda, ailMel1 (AilMel_1.0), GCA_000004335.1, ailMel1
# Pig, Sscrofa10.2, GCA_000003025.4, susScr3
# Pika, OchPri2.0 (ASM16482v1), GCA_000164825.1, ochPri2
# Platyfish, Xipmac4.4.2 (Xiphophorus_maculatus-4.4.2), GCA_000241075.1, none
# Platypus, OANA5 (Ornithorhynchus_anatinus-5.0.1), GCF_000002275.2, ornAna1
# Rabbit, OryCun2.0, GCA_000003625.1, oryCun2
# Rat, Rnor_6.0, GCA_000001895.4, rn6
# Rat, Rnor_5.0, GCA_000001895.3, rn5
# Saccharomyces cerevisiae, R64-1-1, GCA_000146045.2, sacCer3
# Sheep, Oar_v3.1, GCA_000298735.1, oviAri3
# Shrew, sorAra1 (ASM18127v1), GCA_000181275.1, sorAra1
# Sloth, choHof1 (ChoHof1.0), GCA_000164785.1, choHof1
# Spotted gar, LepOcu1, GCA_000242695.1, none
# Squirrel, spetri2 (SpeTri2.0), GCA_000236235.1, speTri2
# Stickleback, BROAD S1 (ASM18067v1), GCA_000180675.1, gasAcu1
# Tarsier, tarSyr1 (Tarsyr1.0), GCA_000164805.1, tarSyr1
# Tasmanian devil, Devil_ref v7.0, GCA_000189315.1, sarHar1
# Tetraodon, TETRAODON 8.0, ?, ?
# Tilapia, Orenil1.0, GCA_000188235.1, none
# Tree Shrew, tupBel1, ?, ?
# Turkey, Turkey_2.01, GCA_000146605.2, melGal1
# Vervet-AGM, ChlSab1.1, GCA_000409795.2, none
# Wallaby, Meug_1.0, ? , ? # have Meug_1.1 on NCBI instead
# Xenopus, JGI 4.2 (v4.2), GCA_000004195.1, xenTro3
# Zebra Finch, taeGut3.2.4 (Taeniopygia_guttata-3.2.4), GCA_000151805.2, taeGut1
# Zebrafish, GRCz10, GCA_000002035.3, danRer10
# Zebrafish, Zv9, GCA_000002035.2, danRer7
#
#
#
#
# Add species/assembly info
#
sub _add_genome_info {
  my ($self, $genome, $doc) = @_;
  defined $genome and defined $doc or
    die "Undefined genome and/or doc arguments";

  #
  # Map the (UCSC) assembly synonym to INSDC assembly accession
  # i.e. an entry in the genome collection db
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
  # Update: 
  #   there's an intersection but there are differences between UCSC
  #   and EnsEMBL supported species/assemblies. If we are to support
  #   just UCSC, that would leave out a significant portion of genomes
  #   which could be rendered (and are requested for TrackHub support)
  #   in the EnsEMBL browser, e.g. EG plants, S.pombe, later could be
  #   worms and others supported by EG.
  #   Assembly hubs could be available but are currently not supported
  #   by Ensembl, it would be just to provide a link to UCSC.
  #   We want here to provide a mechanism complementary to assembly hubs
  #   for situations where the data provider submits hubs for genome
  #   assemblies not supported by UCSC but which are deposited in INSDC
  #   archives (have an accession) and have a fair chance of being 
  #   supported by Ensembl, which now covers a reasonable spectrum of
  #   the vertebrate and non-vertebrate space.
  #   The idea is to let the registry follow a policy compatible with 
  #   the Browser Genome Release Agreement of only allowing the registration 
  #   of track hubs with assemblies that have been submitted to the INSDC 
  #   archives (ENA, GenBank and DDBJ). 
  #   This means that it must be possible for any genome assembly name, 
  #   whether it being a valid UCSC synonym or not, specified in a submitted 
  #   trackhub, to map it to a valid INSDC accession.
  #   The map provided for UCSC db names is only a partial solution, since
  #   it does not cover INSDC deposited assemblies which are supported
  #   by EnsEMBL. 
  #   The strategy is to allow the submitters to follow three main assembly
  #   name specification strategies:
  #   
  #   1. UCSC db name
  #   2. Ensembl assembly name
  #   3. Map name -> INSDC accession
  #   
  #   2nd way allows submitters in ensembl to register their trackhubs and
  #   its supported by consulting Ensembl and Ensembl Genomes meta tables
  #   to see if there's an accession associated to the provided assembly
  #   name.
  #   3rd way is for when everything else fail, there's no other option
  #   than to provide directly the accession.
  #
  # Map the genome assembly name to an INSDC accession
  #
  my $assembly_id;
  my $assembly_syn = $genome->assembly;

  # manage EnsemblPlants genomes which do not have an accession
  return if $self->_handle_ensemblplants_exceptions($assembly_syn, $doc);

  # If the submitter has directly provided a map, this takes precedence
  my $assembly_map = $self->assemblies;
  if (exists $assembly_map->{$assembly_syn}) {
    if ($assembly_map->{$assembly_syn} =~ /^G(CA|CF)_[0-9]+?\.[0-9]+?$/) {
      $assembly_id = $assembly_map->{$assembly_syn};
    } else {
      die sprintf "Assembly accession %s for %s does not comply with INSDC format", $assembly_map->{$assembly_syn}, $assembly_syn;
    }  
  } elsif (exists $ucscdb2insdc->{lc $assembly_syn}) {
    $assembly_id = $ucscdb2insdc->{lc $assembly_syn};
  } else {
    # TODO: Look up the assembly name in the shared genome info Ensembl DB
    #       map it to an accession
  }

  die "Unable to find a valid INSDC accession for genome assembly name $assembly_syn"
    unless defined $assembly_id;

  #
  # Get species (tax id, scientific name, common name)
  # and assembly info from the assembly set table in the GC database
  #
  # my $gc_assembly_set = $self->gc_assembly_set;
  # my $as = $gc_assembly_set->find($assembly_id);
  # die "Unable to find GC assembly set entry for $assembly_id"
  #   unless $as;
  
  # my ($tax_id, $scientific_name, $common_name) = 
  #   ($as->tax_id, $as->scientific_name, $as->common_name);
  # # TODO: taxid and scientific name are mandatory

  # $doc->{species}{tax_id} = $tax_id if $tax_id;
  # $doc->{species}{scientific_name} = $scientific_name if $scientific_name;
  # $doc->{species}{common_name} = $common_name if $common_name;

  # $doc->{assembly}{accession} = $assembly_id;
  # $doc->{assembly}{name} = $as->name;
  # $doc->{assembly}{long_name} = $as->long_name if $as->long_name; # sometimes not defined
  # $doc->{assembly}{synonyms} = $assembly_syn;

  # my $gc_assembly_set = 
  #   from_json(Registry::Utils::slurp_file(Registry->config()->{GenomeCollection}{assembly_set_file}));

  # gc assembly set file is assumed to be compressed (gzip)
  my $buffer;
  my $file = Registry->config()->{GenomeCollection}{assembly_set_file};
  gunzip $file => \$buffer 
    or die "gunzip failed: $GunzipError\n";

  my $gc_assembly_set = from_json($buffer);
  my $as = $gc_assembly_set->{$assembly_id};
  die "Unable to find GC assembly set entry for $assembly_id"
    unless $as;
  
  my ($tax_id, $scientific_name, $common_name) = 
    ($as->{tax_id}, $as->{scientific_name}, $as->{common_name});
  # TODO: taxid and scientific name are mandatory

  $doc->{species}{tax_id} = $tax_id if $tax_id;
  $doc->{species}{scientific_name} = $scientific_name if $scientific_name;
  $doc->{species}{common_name} = $common_name if $common_name;

  $doc->{assembly}{accession} = $assembly_id;
  $doc->{assembly}{name} = $as->{name};
  $doc->{assembly}{long_name} = $as->{long_name} if $as->{long_name}; # sometimes not defined
  $doc->{assembly}{synonyms} = $assembly_syn;

  return;
}

sub _add_genome_browser_links {
  my ($self, $genome, $doc) = @_;
  defined $genome and defined $doc or
    die "Undefined genome and/or doc arguments";

  my $assemblysyn = $genome->assembly;
  defined $assemblysyn or die "Couldn't get assembly identifier from hub genome";

  my $hub = $doc->{hub};
  defined $hub->{url} or die "Couldn't get hub URL";

  my $is_assembly_hub = $hub->{assembly};
  defined $is_assembly_hub or 
    die "Couldn't detect assembly hub";

  my ($assembly_accession, $assembly_name) =
    ($doc->{assembly}{accession}, $doc->{assembly}{name});
  defined $assembly_accession and defined $assembly_name or
    die "Assembly accession|name not defined";

  #
  # UCSC browser link
  #
  # Provide different links in case it's an assembly hub
  # or an assembly supported by UCSC
  if ($is_assembly_hub) { 
    # see http://genome.ucsc.edu/goldenPath/help/hubQuickStartAssembly.html#blatGbib
     $doc->{hub}{browser_links}{ucsc} = sprintf "http://genome.ucsc.edu/cgi-bin/hgGateway?hubUrl=%s", $hub->{url};
  } elsif (exists $ucscdb2insdc->{lc $assemblysyn}) {
    # assembly supported by UCSC
    $doc->{hub}{browser_links}{ucsc} = 
      # sprintf "http://genome.ucsc.edu/cgi-bin/hgTracks?db=%s&hubUrl=%s", $asseblysyn, $hub->{url};
      sprintf "http://genome.ucsc.edu/cgi-bin/hgHubConnect?db=%s&hubUrl=%s&hgHub_do_redirect=on&hgHubConnect.remakeTrackHub=on", $assemblysyn, $hub->{url};
  }

  #
  # EnsEMBL browser link
  #
  return if $is_assembly_hub; # Ensembl does not support assembly hubs at the moment

  my ($domain, $species) = 
    ('http://### DIVISION ###.ensembl.org', $doc->{species}{scientific_name});
  defined $species or die "Couldn't get species to build Ensembl URL";

  $species = join('_', (split(/\s/, $species))[0 .. 1]);
  $species =~ /^\w+_\w+$/ or die "Couldn't get the required species name to build the Ensembl URL";

  my $division;

  # 
  # First the special cases:
  # - human (grch38.* -> www, grch37.* -> grch37)
  # - mouse (only grcm38.* supported -> www)
  # - fruitfly (Release 6 up-to-date, Release 5 from Dec 2014 backward)
  # - rat (Rnor_6.0 up-to-date, Rnor_5.0 from Mar 2015 backward)
  # - zebrafish (GRCz10 up-to-date, Zv9 from Mar 2015 backward)
  #
  # The division for other assemblies is determined by looking up
  # in the ensembl genomes info DB by assembly ID or tax ID (name?)
  #
  if ($species =~ /homo_sapiens/i) { # if it's human assembly
    # only GRCh38.* and GRCh37.* assemblies are supported,
    # domain is different in the two cases
    if ($assembly_name =~ /grch38/i) {
      $division = 'www';
    } elsif ($assembly_name =~ /grch37/i) {
      $division = 'grch37';
    } # other human assemblies are not supported

  } elsif ($species =~ /mus_musculus/i) { # if it's mouse assembly
    # any GRCm38 patch is supported, other assemblies are not
    $division = 'www' if $assembly_name =~ /grcm38/i;
  } elsif ($species =~ /rattus_norvegicus/i) { 
    # if it's rat assembly must take archive into account
    if ($assembly_name =~ /Rnor_6/i) {
      $division = 'www';
    } elsif ($assembly_name =~ /Rnor_5/i) {
      $division = 'mar2015.archive';
    }
  } elsif ($species =~ /danio_rerio/i) { 
    # if it's zebrafish assembly must take archive into account
    if ($assembly_name =~ /GRCz10/i) {
      $division = 'www';
    } elsif ($assembly_name =~ /Zv9/i) {
      $division = 'mar2015.archive';
    }
  } elsif ($species =~ /drosophila_melanogaster/i) { 
    # if it's fruitfly assembly must take archive into account
    if ($assembly_name =~ /Release 6/i) {
      $division = 'www';
    } elsif ($assembly_name =~ /Release 5/i) {
      $division = 'dec2014.archive';
    }
  } else {
    # Look up division in shared genome DB, by using assembly accession,
    # when provided, or assembly name

    # create an adaptor to work with genomes
    my $gdba = Bio::EnsEMBL::Utils::MetaData::DBSQL::GenomeInfoAdaptor->build_adaptor();
    
    # first see if we can get by assembly accession
    my ($genome, $genome_division);
    if ($assembly_accession =~ /^GC/) {
      $genome = $gdba->fetch_by_assembly_id($assembly_accession);
    } else { 
      # assembly accession not available: try fetch by assembly name
      #
      # TODO: there's no method in GenomeInfoAdaptor to fetch by assembly name. Ask Dan S to provide one
      #
      # Can still fetch by taxonomy ID
      $genome = $gdba->fetch_all_by_taxonomy_id($doc->{species}{tax_id})->[0] if $doc->{species}{tax_id};
      
    }
    # disconnect otherwise will end up with lots of sleeping connections on the
    # public server causing "Too many connections" error
    $gdba->{dbc}->disconnect_if_idle && 
      die "Couldn't close connection to ensemblgenomes info DB";

    $genome_division = $genome->division if $genome;
    if (defined $genome_division && $genome_division =~ /^Ensembl/) {
      if ($genome_division eq 'Ensembl') {
	$division = 'www';
      } else {
	($division = lc $genome_division) =~ s/ensembl//i;
      }
    }
  }

  if ($division) {
    $domain =~ s/### DIVISION ###/$division/;
    my $shortLabel = $hub->{shortLabel};
    $shortLabel =~ s/\s/_/g;
    if ($division =~ /archive/) {
      $doc->{hub}{browser_links}{ensembl} =
	sprintf "%s/%s/Location/View?contigviewbottom=url:%s;name=%s;format=TRACKHUB;#modal_user_data", $domain, $species, $hub->{url}, $shortLabel;
    } else {
      $doc->{hub}{browser_links}{ensembl} =
	sprintf "%s/TrackHub?url=%s;species=%s;name=%s;registry=1", $domain, $hub->{url}, $species, $shortLabel;
    }
  }
  
  return;
}

sub _handle_ensemblplants_exceptions {
  my ($self, $assembly_name, $doc) = @_;

  return 0 unless $assembly_name eq 'v0117-2013Aug' or # Oryza longistaminata 
    $assembly_name eq 'PRJEB4137' or # Oryza rufipogon
      $assembly_name =~ 'IWGSC1|TGACv1' or # Triticum aestivum
	  $assembly_name eq 'AGPv4'; # Zea mays

  if ($assembly_name eq 'AGPv4') { # Zea mays
    $doc->{species}{tax_id} = 4577;
    $doc->{species}{scientific_name} = 'Zea mays';
    $doc->{species}{common_name} = 'maize';
        
  } elsif ($assembly_name =~ 'IWGSC1|TGACv1') { # Triticum aestivum
    $doc->{species}{tax_id} = 4565;
    $doc->{species}{scientific_name} = 'Triticum aestivum';
    $doc->{species}{common_name} = 'bread wheat';
    
  } elsif ($assembly_name eq 'PRJEB4137') { # Oryza rufipogon
    $doc->{species}{tax_id} = 4529;
    $doc->{species}{scientific_name} = 'Oryza rufipogon';
    $doc->{species}{common_name} = 'common wild rice';

  } else { # Oryza longistaminata 
    $doc->{species}{tax_id} = 4528;
    $doc->{species}{scientific_name} = 'Oryza longistaminata';
    $doc->{species}{common_name} = 'long-staminate rice';

  } 

  $doc->{assembly}{accession} = 'NA';
  $doc->{assembly}{name} = $assembly_name;
  $doc->{assembly}{synonyms} = $assembly_name;

  return 1;
}

1;
