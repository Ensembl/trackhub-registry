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

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

local $SIG{__WARN__} = sub {};

use JSON;
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST/;

use Catalyst::Test 'Registry';

use Registry::Utils;
use Registry::Indexer;

my $config = Registry->config()->{'Model::Search'};
my $indexer = Registry::Indexer->new(dir   => "$Bin/trackhub-examples/",
				     trackhub => {
						  index => $config->{trackhub}{index},
						  type  => $config->{trackhub}{type},
						  mapping => 'trackhub_mappings.json'
						 }
				    );

$indexer->index_users();

my $server = 'http://127.0.0.1:3000';
my $ua = LWP::UserAgent->new;
my ($user, $pass) = ('trackhub1', 'trackhub1');

my $auth_token = login($server, $user, $pass);

my $start_mem = get_mem();
print "start mem usage: ${start_mem}mb\n";

for my $i (0..100) {
  my $request = POST("$server/api/trackhub",
		     'Content-type' => 'application/json',
		     'Content'      => to_json({ url => 'http://www.ebi.ac.uk/~tapanari/data/test2/DRP000315/hub.txt', 
						 assemblies => { "IRGSP-1.0" => 'GCA_000002775.2' }
					       }));
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response = $ua->request($request);
  die sprintf "Cannot post hub at %dth attempt: %d", $i, $response->code
    unless $response->is_success;
  # print "${i} requests\n" if ( $i % 1000 ) == 0;
}

my $end_mem = get_mem();

print "end mem usage: ${end_mem}mb\n";
print "diff " . ($end_mem - $start_mem) . "mb\n";
 
logout($server, $user, $auth_token);

# Delete the index created
$indexer->delete();

sub login {
  my ($server, $user, $pass) = @_;

  my $request = GET("$server/api/login");
  $request->headers->authorization_basic($user, $pass);
  
  my $response = $ua->request($request);
  return from_json($response->content)->{auth_token}
    if $response->is_success;
  
  die sprintf "Cannot login: %s", $response->code;
}

sub logout {
  my ($server, $user, $auth_token) = @_;

  my $request = GET("$server/api/logout");
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response = $ua->request($request);
  
  die sprintf "Couldn't logout: %s", $response->code
    unless $response->is_success;
}

sub get_mem {
  my $mem = `grep VmRSS /proc/$$/status`;
  return [split(qr/\s+/, $mem)]->[1] / 1024;
}

