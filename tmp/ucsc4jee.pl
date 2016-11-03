#!/usr/bin/env perl

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
  };

foreach my $syn (keys %{$ucscdb2insdc}) {
  printf "%s\t%s\n", $syn, $ucscdb2insdc->{$syn};
}
