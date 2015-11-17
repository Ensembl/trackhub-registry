use strict;
use warnings;

use JSON;
use HTTP::Request::Common;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new;
my $server = 'https://127.0.0.1:3000';
my $endpoint = '/api/login';
my ($user, $pass) = ('trackhub1', 'trackhub1');

my $request = GET($server.$ext);
$request->headers->authorization_basic($user, $pass);

my $response = $ua->request($request);
my $auth_token;
if ($response->is_success) {
  $auth_token = from_json($response->content)->{auth_token};
  print "Logged in\n" if $auth_token;
} else {
  die "Couldn't login, reason: ", $response->content, "\n";
}
