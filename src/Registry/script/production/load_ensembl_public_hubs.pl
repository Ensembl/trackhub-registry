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

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common;
use LWP::UserAgent;
use Data::Dumper;

$| = 1;
my $ua = LWP::UserAgent->new;
my $server = 'https://beta.trackhubregistry.org';
# my $server = 'http://localhost:3000';

@ARGV == 2 or die "Usage: load_ensembl_public_hubs.pl <user> <password>\n";

my ($user, $pass) = ($ARGV[0], $ARGV[1]); 
my $request = GET("$server/api/login");
$request->headers->authorization_basic($user, $pass);
my $response = $ua->request($request);
my $auth_token;
if ($response->is_success) {
  $auth_token = from_json($response->content)->{auth_token};
  print "Logged in [$auth_token]\n" if $auth_token;
} else {
  die sprintf "Couldn't login: %s [%d]", $response->content, $response->code;
}

my $hubs = 
  [
   { # Blueprint GRCh38 Hub
    url => "http://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub"
   },
   { # Blueprint GRCh37 Hub
    url => 'http://ftp.ebi.ac.uk/pub/databases/blueprint/releases/20150128/homo_sapiens/hub/hub.txt'
   },
   { # ENCODE Analysis Hub (2011)
     url => 'http://ftp.ebi.ac.uk/pub/databases/ensembl/encode/integration_data_jan2011/hub.txt'
   },
   # Error: parent track miRNA_expression is missing
   # { # Broad Improved Canine Annotation v1
   #  url => 'https://www.broadinstitute.org/ftp/pub/vgb/dog/trackHub/hub.txt'
   # },
   { # Cancer genome polyA site & usage
    url => 'http://johnlab.org/xpad/Hub/UCSC.txt'
   },
   { # CEMT (CEEHRC) Epigenomic Data tracks from BCGSC, Vancouver
    url => 'http://www.bcgsc.ca/downloads/edcc/data/CEMT/hub/bcgsc_datahub.txt'
   },
   # Error 503: service temporarily unavailable
   { # CREST IHEC Epigenome Project Hub
    url => 'http://epigenome.cbrc.jp/files/jst/hub/hub.txt'
   },
   # Not Found
   # { # Deutsches Epigenome Programm (DEEP)
   #  url => 'https://otpfiles.dkfz.de/DEEP-trackhubs/hub.txt'
   # },
   # contains tair10 which is assembly hub not directly supported by UCSC
   # but we still have manual mapping for it since it indicates the
   # assembly accession ID in the hub description file
   # Error 504: gateway time out
   # Error: "error":"Unable to find GC assembly set entry for GCF_000001515.3 at Translator.pm line 946
   { # DNA Methylation Hundreds of analyzed methylomes from bisulfite sequencing data
    url => 'http://smithlab.usc.edu/trackdata/methylation/hub.txt',
    assemblies => { tair10 => 'GCA_000001735.1' }
   },
   # Error: utf8 \"\\xA2\" does not map to Unicode
   # Run isutf8 (from moreutils package) on trackDb.txt which confirms:
   # trackDb.txt: line 2654, char 1, byte offset 429: invalid UTF-8 code
   # { # EDACC hosted Roadmap Epigenomics Hub
   #  url => 'http://genboree.org/EdaccData/trackHub/hub.txt'
   # },
   { # Sanger Genome Reference Informatics Team: Genome issues and other features
    url => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt'
   },
   { # McGill Epigenomics Mapping Centre, Montreal, Quebec, Canada
    url => 'http://epigenomesportal.ca/hub/hub.txt'
   },
   { # Predicted microRNA target sites in GENCODE transcripts
    url => 'http://www.mircode.org/ucscHub/hub.txt'
   },
   { # Protein-coding potential as determined by PhyloCSF
    url => 'http://www.broadinstitute.org/compbio1/PhyloCSFtracks/trackHub/hub.txt'
   },
   { # Porcine DNA methylation and gene transcription
    url => 'http://faang.abgc.asg.wur.nl/TJ_Tabasco/hub.txt'
   },
   # MASSIVE, HOLD ON
   # { # Roadmap Epigenomics Integrative Analysis Hub
   #  url => 'http://vizhub.wustl.edu/VizHub/RoadmapIntegrative.txt'
   # },
   # TIMED OUT
   { # Sense/antisense gene/exon expression using Affymetrix exon array from South Dakota State University, USA
    url => 'http://bioinformatics.sdstate.edu/datasets/2012-NAT/hub.txt'
   },
   { # Translation Initiation Sites (TIS)
    url => 'http://gengastro.1med.uni-kiel.de/suppl/footprint/Hub/tisHub.txt'
   },
   { # Ultra conserved Elements in the Human Genome Science 304(5675) pp.1321-1325 (2004)
    url => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/GillBejerano/hub.txt'
   },
   # NOT FOUND
   # { # UMassMed H3K4me3 ChIP-seq data for Autistic brains
   #  url => 'https://zlab.umassmed.edu/zlab/publications/UMassMedZHub/hub.txt'
   # },
   { # Variant information for the NHGRI-1 zebrafish line
    url => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt'
   },
  ];

foreach my $hub (@{$hubs}) {
  printf "Submitting hub at %s...", $hub->{url}; 
  $request = POST("$server/api/trackhub",
                  'Content-type' => 'application/json',
                  'Content'      => to_json($hub));
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  $response = $ua->request($request);
  if ($response->code == 201) {
    print " Done.\n";
  } else {
    printf "\nCouldn't register hub at %s: %s [%d]", $hub->{url}, $response->content, $response->code;
  } 
}

# Logout 
$request = GET("$server/api/logout");
$request->headers->header(user       => $user);
$request->headers->header(auth_token => $auth_token);
if ($response->is_success) {
  print "Logged out\n";
} else {
  print "Unable to logout\n";
} 
