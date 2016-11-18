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
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new;

my $server = 'http://localhost:3000';

use Search::Elasticsearch;

my $es = Search::Elasticsearch->new();
my $results =
  $es->search(index => 'test',
	      type  => 'trackdb',
	      body => {
		       # filter => {
		       # 		  bool => {
		       # 			   must => { term => { 'public' => 1 } },
		       # 			   should =>  [ { term => { 'assembly.name' => 'GRCz10' } }, { term => { 'assembly.synonyms' => 'GRCz10'} } ]
		       # 			  }
		       # 		  # or => [ { term => { 'assembly.name' => 'GRCz10' } }, { term => { 'assembly.synonyms' => 'GRCz10'} } ],
		       # 		  # and => [ { term => { 'public' => 1 } } ]
		       # 		 }
		       aggs => {
				species => { 
					    terms => { field => 'species.scientific_name', size  => 0 },
					    aggs  => {
						      ass_name => {
								   terms => { field => 'assembly.name', size => 0 },
								   aggs => {
									    ass_syn => {
											terms => { field => 'assembly.synonyms', size => 0 },
											aggs => {
												 ass_acc => { terms => { field => 'assembly.accession', size => 0 } }
												}
										       }
									   }
								  }
						     }
					   },
			       }
		      }
	     );

my $aggs;
foreach my $species_agg (@{$results->{aggregations}{species}{buckets}}) {
  my $species = $species_agg->{key};
  foreach my $ass_name_agg (@{$species_agg->{ass_name}{buckets}}) {
    my $ass_name = $ass_name_agg->{key};
    foreach my $ass_syn_agg (@{$ass_name_agg->{ass_syn}{buckets}}) {
      my $ass_syn = $ass_syn_agg->{key};
      foreach my $ass_acc_agg (@{$ass_syn_agg->{ass_acc}{buckets}}) {
	my $ass_acc = $ass_acc_agg->{key};
	push @{$aggs->{$species}},
	  {
	   name => $ass_name,
	   synonyms => $ass_syn,
	   accession => $ass_acc
	  }
      }
    }
  }
}

use Data::Dumper;
print Dumper $aggs;
# print $results->{hits}{total}, "\n";
exit;

#my $server = 'http://beta.trackhubregistry.org';

my $request = GET("$server/api/info/hubs_per_assembly/Culpip1.0");
my $response = $ua->request($request);
if ($response->is_success) {
  print Dumper from_json($response->content);
} else {
  die sprintf "Couldn't query: %s [%d]", $response->content, $response->code;
}

$request = GET("$server/api/info/tracks_per_assembly/culpip1.0");
$response = $ua->request($request);
if ($response->is_success) {
  print Dumper from_json($response->content);
} else {
  die sprintf "Couldn't query: %s [%d]", $response->content, $response->code;
}

exit;

my $server = 'http://beta.trackhubregistry.org';
my $request;

# number of trackhubs
$request = GET("$server/api/info/trackhubs");
my $response = $ua->request($request);
if ($response->is_success) {
  printf "Number of trackhubs: %d\n", scalar @{from_json($response->content)};
} else {
  die sprintf "Couldn't query: %s [%d]", $response->content, $response->code;
}

# number of species/assemblies
$request = GET("$server/api/info/assemblies");
my $response = $ua->request($request);
if ($response->is_success) {
  my $content = from_json($response->content);
  printf "Number of species: %d\n", scalar keys %{$content};
  my $assemblies =  0;
  map { $assemblies += scalar @{$content->{$_}} } keys %{$content};
  printf "Number of assemblies: %d\n", $assemblies;
} else {
  die sprintf "Couldn't query: %s [%d]", $response->content, $response->code;
}
  
done_testing();
