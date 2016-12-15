#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

BEGIN { $ENV{CATALYST_DEBUG} = 0 }

use JSON;
use DBI;

# Step1: Read json dump and store it in a data structure
my $json;

open my $fhr, "<", "../prod_elastic_dumps/trackhubs_v1_data.json";
open my $fhw, ">", "../prod_elastic_dumps/qc_checked/trackhubs_v1_data_qc.json";

use Data::Dumper;

my $user_info = {};
my $counter   = 0;
my $limit     = 1000;

while (<$fhr>) {
#	if ( $counter >= $limit ) {
#		last;
#	}
	my $all_data      = decode_json($_);
	my $all_meta_data = $all_data->{_source}->{data};

	#remember to handle empty file_data
	
	foreach my $meta_data ( @{$all_meta_data} ) {
		foreach my $key (keys %{$meta_data} ) {
            
			if (length($key) <= 1){
			 delete $meta_data->{$key};
			 next;
			}
			
			
			if ($key =~ /^[a-zA-Z_]*$/){
				if($key =~ /^[ATCGN]+$/){
			      delete $meta_data->{$key};
				}
			}else{
			  delete $meta_data->{$key};
			}
		}

	}
	
	my $all_file_type_data = $all_data->{_source}->{file_type};
	foreach my $key (keys %{$all_file_type_data} ) {
		
		if (length($key) <= 1){
			 delete $all_file_type_data->{$key};
			 next;
		}
	}
	
	my $encoded_json = encode_json $all_data;
	print $fhw $encoded_json;
	print $fhw "\n";
	$counter++;
	
	

}

close $fhr;
close $fhw;


