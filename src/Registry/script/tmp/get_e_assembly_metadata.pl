#!/usr/bin/env perl
# Copyright [2015-2018] EMBL-European Bioinformatics Institute
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

use Data::Dumper;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::ApiVersion 'software_version';

my $registry = 'Bio::EnsEMBL::Registry';
$registry->load_registry_from_db(-host => 'ensembldb.ensembl.org',
                                 -user => 'anonymous',
                                 -db_version => software_version);
				 
my @species = qw ( anas_platyrhynchos
anolis_carolinensis
astyanax_mexicanus
bos_taurus
caenorhabditis_elegans
callithrix_jacchus
canis_familiaris
cavia_porcellus
chlorocebus_sabaeus
choloepus_hoffmanni
ciona_intestinalis
ciona_savignyi
danio_rerio
dasypus_novemcinctus
dipodomys_ordii
drosophila_melanogaster
echinops_telfairi
equus_caballus
erinaceus_europaeus
felis_catus
ficedula_albicollis
gadus_morhua
gallus_gallus
gasterosteus_aculeatus
gorilla_gorilla
homo_sapiens
ictidomys_tridecemlineatus
latimeria_chalumnae
lepisosteus_oculatus
loxodonta_africana
macaca_mulatta
macropus_eugenii
meleagris_gallopavo
microcebus_murinus
monodelphis_domestica
mus_musculus
mustela_putorius_furo
myotis_lucifugus
nomascus_leucogenys
ochotona_princeps
oreochromis_niloticus
ornithorhynchus_anatinus
oryctolagus_cuniculus
oryzias_latipes
otolemur_garnettii
ovis_aries
pan_troglodytes
papio_anubis
pelodiscus_sinensis
petromyzon_marinus
poecilia_formosa
pongo_abelii
procavia_capensis
pteropus_vampyrus
rattus_norvegicus
saccharomyces_cerevisiae
sarcophilus_harrisii
sorex_araneus
sus_scrofa
taeniopygia_guttata
takifugu_rubripes
tarsius_syrichta
tetraodon_nigroviridis
tupaia_belangeri
tursiops_truncatus
vicugna_pacos
xenopus_tropicalis
xiphophorus_maculatus);

my @meta_keys = qw(assembly.name assembly.accession assembly.ucsc_alias);

open my $FH, ">","tmp.txt" or die "Cannot open file: $!\n";
foreach my $species (@species) {
  my $meta_adaptor = $registry->get_adaptor($species, 'Core', 'MetaContainer');

  my %metas;
  foreach my $meta_key (@meta_keys) {
    $metas{$meta_key} = eval { join(',', @{ $meta_adaptor->list_value_by_key($meta_key) }); };
    if ($@) {
      $metas{$meta_key} = 'NONE';
    }

    # $metas{$meta_key} = $meta_adaptor->single_value_by_key($meta_key);
  }

  printf $FH "%s\t%s\t%s\t%s\n", $species, $metas{'assembly.name'}, $metas{'assembly.accession'}, $metas{'assembly.ucsc_alias'};
}
close $FH;
