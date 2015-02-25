use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use_ok 'Registry::GenomeAssembly::Schema';

my $schema = Registry::GenomeAssembly::Schema->connect("DBI:Oracle:host=ora-vm5-003.ebi.ac.uk;sid=ETAPRO;port=1571", 
						       'gc_reader', 
						       'reader', 
						       { 'RaiseError' => 1, 'PrintError' => 0 });
isa_ok($schema, 'Registry::GenomeAssembly::Schema');

# my $assembly_sets = $schema->resultset('GCAssemblySet');
# use Data::Dumper; print Dumper($assembly_sets);
# foreach my $set ($schema->resultset('GCAssemblySet')->all) {
#   printf "%s\t%s\n", $set->set_acc, $set->name;
# }

my $assembly_set = $schema->resultset('GCAssemblySet')->find('GCA_000001405.15');

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
