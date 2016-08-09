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

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../../registry_testing.conf";
}

use_ok 'Registry::GenomeAssembly::Schema';

my $schema = Registry::GenomeAssembly::Schema->connect("DBI:Oracle:host=ora-vm5-003.ebi.ac.uk;sid=ETAPRO;port=1571", 
						       'gc_reader', 
						       'reader', 
						       { 'RaiseError' => 1, 'PrintError' => 0 });
isa_ok($schema, 'Registry::GenomeAssembly::Schema');

my $set_acc = 'GCA_000001405.15';

note "Testing access to $set_acc data";
my $assembly_set = $schema->resultset('GCAssemblySet')->find($set_acc);

my %expected = (
		'long_name' => 'Genome Reference Consortium Human Build 38',
		'set_acc' => 'GCA_000001405.15',
		'genome_representation' => 'full',
		'common_name' => 'human',
		'set_chain' => 'GCA_000001405',
		'assembly_level' => 'chromosome',
		'refseq_set_acc' => 'GCF_000001405.26',
		'set_version' => '15',
		'name' => 'GRCh38',
		'is_refseq' => 'N',
		'scientific_name' => 'Homo sapiens',
		'tax_id' => '9606',
		'is_patch' => 'N',
	       );

map { is($assembly_set->$_, $expected{$_}, "Correct $_") } keys %expected;

done_testing();
