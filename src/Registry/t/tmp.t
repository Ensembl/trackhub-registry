use strict;
use warnings;
use Data::Dumper;

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new;
my $server = 'http://127.0.0.1:3000';
my ($user, $pass) = ('trackhub1', 'trackhub1'); # ('etapanari', 'ensemblplants');
my $request = GET("$server/api/login");
$request->headers->authorization_basic($user, $pass);
my $response = $ua->request($request);
my $content = from_json($response->content);
my $auth_token = $content->{auth_token};
print "Logged in\n" if $auth_token;

$request = GET("$server/api/trackdb/AVCzG8pAaLx8j0yTm-ob");
$request->headers->header(user       => $user);
$request->headers->header(auth_token => $auth_token);
$response = $ua->request($request);
my $doc;
if ($response->is_success) {
  $doc = from_json($response->content);
} else {  
  print "Couldn't get trackDB\n";
}

  # $request = POST('/api/trackhub?permissive=1',
  # 		  'Content-type' => 'application/json',
  # 		  'Content'      => to_json({ url => 'http://www.ebi.ac.uk/~tapanari/data/test/SRP036860/hub.txt', 
  # 					      assemblies => { "JGI2.0" => 'GCA_000002775.2' }
  # 					    }));
  # $request->headers->header(user       => 'trackhub1');
  # $request->headers->header(auth_token => $auth_token);
  # ok($response = request($request), 'POST request to /api/trackhub');
  # ok($response->is_success, 'Request successful 2xx');
  # is($response->content_type, 'application/json', 'JSON content type');
  # print Dumper $response;
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
$request = GET("$server/api/logout");
$request->headers->header(user       => $user);
$request->headers->header(auth_token => $auth_token);
if ($response->is_success) {
  print "Logged out\n";
} else {
  print "Unable to logout\n";
} 
