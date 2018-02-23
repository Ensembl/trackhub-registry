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

#
# A script to dump the content of the genome assembly set table
# from the Genome Collection database.
# The output file is used to read the association between genome
# assembly sets and species during translation of a remote hub
#
# NOTE: this script can be used only inside the EBI-Wellcome Trust
# Genome Campus network.
#

use strict;
use warnings;

$| = 1;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use Getopt::Long;
use Pod::Usage;
use JSON;
use Registry::Utils;
use Registry::GenomeAssembly::Schema;

# default option values
my $help = 0;
my $outfile = 'gc_assembly_set.json';

# parse command-line arguments
my $options_ok =
  GetOptions("outfile|o=s" => \$outfile,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

my $schema = Registry::GenomeAssembly::Schema->connect("DBI:Oracle:host=ora-vm-066.ebi.ac.uk;sid=ETAPRO;port=1571", 
						       'gc_reader', 
						       'reader', 
						       { 'RaiseError' => 1, 'PrintError' => 0 });

my $rs = $schema->resultset('GCAssemblySet');
my $assembly_sets;

while (my $as = $rs->next) {
  my %data = $as->get_columns;
  $assembly_sets->{$data{set_acc}} = \%data;
}

open my $FH, "$outfile","w" or die "Cannot open file: $!\n";
print $FH to_json($assembly_sets, { utf8 => 1, pretty => 1 });
close $FH;

__END__

=head1 NAME

dump_genome_assembly_set.pl - Write the content of the GC assembly_set table to JSON

=head1 SYNOPSIS

dump_genome_assembly_set.pl [options]

   -o --outfile         output file [default: gc_assembly_set.json]
   -h --help            display this help and exits

=cut
