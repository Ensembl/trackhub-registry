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
# use Test::More;
use Data::Dumper;

# BEGIN {
#   use FindBin qw/$Bin/;
#   use lib "$Bin/../../lib";
#   $ENV{CATALYST_CONFIG} = "$Bin/../../registry_testing.conf";
# }

# local $SIG{__WARN__} = sub {};

use JSON;
use LWP;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;

use HTTP::Request::Common;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new;


# my $server = 'http://193.62.54.43:3000';
my $server = 'http://127.0.0.1:3000';
my $request = GET("$server/api/login");
$request->headers->authorization_basic('trackhub1', 'trackhub1');
my $response = $ua->request($request);
my $content = from_json($response->content);
my $auth_token = $content->{auth_token};
unless ($auth_token) {
  die "Unable to login\n";
} else {
  print "Logged in.\n";
}

$request = POST("$server/api/trackhub?permissive=1",
		'Content-type' => 'application/json',
		'Content'      => to_json({ 
					   # url => 'http://www.ebi.ac.uk/~tapanari/data/test/SRP022925/hub.txt', 
					   # url => 'http://www.ebi.ac.uk/~tapanari/data/test2/SRP061745/hub.txt', 
					   # assemblies => { "IRGSP-1.0" => 'GCA_000005425.2' }
					   # assemblies => { MA1 => 'GCA_000005425.2' }
					   # url => 'ftp://ftp.ensemblgenomes.org/pub/misc_data/TrackHubs/SRP050323/hub.txt', 
					   # url => 'http://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub/hub.txt'
					   # url => 'http://smithlab.usc.edu/trackdata/methylation'
					   url => 'http://fantom.gsc.riken.jp/5/datahub/hub.txt'
					  }));
$request->headers->header(user       => 'trackhub1');
$request->headers->header(auth_token => $auth_token);
$response = $ua->request($request);
if ($response->is_success) {
  print "OK.\n";
  print Dumper from_json($response->content), "\n";
} else {
  print from_json($response->content)->{error}, "\n";
}
  
# Logout 
$request = GET("$server/api/logout");
$request->headers->header(user       => 'trackhub1');
$request->headers->header(auth_token => $auth_token);
$response = $ua->request($request);
if ($response->is_success) {
  print "Logged out.\n";
} else {
  print "Unable to logout.\n";
}
