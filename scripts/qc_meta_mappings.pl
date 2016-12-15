#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

BEGIN { $ENV{CATALYST_DEBUG} = 0 }

use JSON;
use DBI;

# Step1: Read json dump and store it in a data structure
my $json;

open my $fhr, "<", "../prod_elastic_dumps/trackhubs_v1_mapping.json";
open my $fhw, ">", "../prod_elastic_dumps/qc_checked/trackhubs_v1_mapping_qc.json";

use Data::Dumper;

my $user_info = {};
my $counter   = 0;
my $limit     = 1000;

while (<$fhr>) {
#	if ( $counter >= $limit ) {
#		last;
#	}
	my $all_data = decode_json($_);
	
	my $all_meta_data = $all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{data}->{properties};
	#print Dumper $all_meta_data;

		
	foreach my $key (keys %{$all_meta_data} ) {
		
		
		print "KEY PRESENT $key\n" if $key ~~ qw(A 1 2 3 4 5 6 7 8);
		
		if (length($key) <= 1){
			 delete $all_meta_data->{$key};
			 next;
		}
		
		if ($key ~~ qw(A 1 2 3 4 5 6 7 8)){
			print "KEY PRESENT...Exiting\n";
		}
		
		if ($key =~ /^[a-zA-Z_]*$/){
			if($key =~ /^[ATCGN]+$/){
				print "Reached here1   $key\n";
			    delete $all_meta_data->{$key};
			}
		  #print "KEY OK+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++=> $key \n";
		}else{
		  delete $all_meta_data->{$key};
		}
	}
	
	#fix file type
	my $all_file_type_data = $all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{file_type}->{properties};
	foreach my $key (keys %{$all_file_type_data} ) {
		
		if (length($key) <= 1){
			 delete $all_file_type_data->{$key};
			 next;
		}
	}

	#fix type mapping
	my $type_mapping = $all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{type};
	$all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{type} = {'type' => 'keyword'};

	#fix assembly synonyms
	my $assembly_synonym_mapping = $all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{assembly}->{properties}->{synonyms};
	print STDERR "============before==========\n";
    print STDERR Dumper($assembly_synonym_mapping);
    print STDERR "===========================\n";
	
	$all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{assembly}->{properties}->{synonyms} = {'type' => 'text', 'fielddata'=> 'true'};
	$assembly_synonym_mapping = $all_data->{trackhubs_v1}->{mappings}->{trackdb}->{properties}->{assembly}->{properties}->{synonyms};
	print STDERR "=============after===========\n";
    print STDERR Dumper($assembly_synonym_mapping);
    print STDERR "===========================\n";
	
	my $encoded_json = encode_json $all_data;
	print $fhw $encoded_json;
	print $fhw "\n";
	$counter++;

}

close $fhr;
close $fhw;


