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
use HTTP::Request::Common qw/GET POST PUT DELETE/;

use Catalyst::Test 'Registry';

use Registry::Utils; # es_running, slurp_file
use Registry::Indexer; # index a couple of sample documents

SKIP: {

  #
  # Authenticate
  #
  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};
  
  $request = POST('/api/trackhub?permissive=1',
		  'Content-type' => 'application/json',
		  'Content'      => to_json({ url => 'http://www.ebi.ac.uk/~tapanari/data/test/SRP036860/hub.txt', 
					      assemblies => { "JGI2.0" => 'GCA_000002775.2' }
					    }));
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'POST request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  print Dumper $response;
  # $content = from_json($response->content);
  # is(scalar @{$content}, 3, "Correct number of trackdb docs created");
  # my @ids = map { $_ } @{$response->headers->{location}};

  # is(scalar @ids, 3, 'Corrent number of IDs');

  #
  # /api/trackdb (GET): get list 
  #

  #
  # /api/trackhub (GET): get list of trackhubs
  #
  # $request = GET('/api/trackhub');
  # $request->headers->header(user       => 'trackhub1');
  # $request->headers->header(auth_token => $auth_token);
  # ok($response = request($request), 'GET request to /api/trackdb');
  # ok($response->is_success, 'Request successful 2xx');
  # is($response->content_type, 'application/json', 'JSON content type');
  # $content = from_json($response->content);
  # use Data::Dumper; print Dumper $content;

  #
  # /api/trackdb (GET): get trackdb with the given ID
  #
  # $request = GET($ids[0]);
  # $request->headers->header(user       => 'trackhub1');
  # $request->headers->header(auth_token => $auth_token);
  # ok($response = request($request), sprintf "GET request to %s", $ids[0]);
  # ok($response->is_success, 'Request successful 2xx');
  # is($response->content_type, 'application/json', 'JSON content type');
  # $content = from_json($response->content);
  # open my $FH, ">tmp.json" or die "Cannot open file: $!\n";
  # use Data::Dumper; print $FH Dumper $content;
  
  # Logout 
  $request = GET('/api/logout');
  $request->headers->header(user       => 'trackhub1');
  $request->headers->header(auth_token => $auth_token);
  ok($response = request($request), 'GET request to /api/logout');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  $content = from_json($response->content);
  like($content->{message}, qr/logged out/, 'Logged out');

}

done_testing();
