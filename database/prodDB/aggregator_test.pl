#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

BEGIN { $ENV{CATALYST_DEBUG} = 0 }

use JSON;
use DBI;

# Step1: Read json dump and store it in a data structure
my $json;

open my $fh, "<", "../prod_elastic_dumps/trackhubs_v1_data.json";
use Data::Dumper;

my $trackdb_species = {};
my $counter   = 0;
while (<$fh>) {

	my $data = decode_json($_);
	my $source = $data->{_source};
	if ($source->{public} == 1) {
	print Dumper($source->{species}->{scientific_name});
	$trackdb_species->{$source->{species}->{scientific_name}}++;
	$counter++;
	}
}

print Dumper sort $trackdb_species;
print "Number of docs  $counter\n";


