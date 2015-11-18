use strict;
use warnings;

use JSON;
use HTTP::Request::Common;
use LWP::UserAgent; # install LWP::Protocol::https as well

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
my ($user, $pass) = ('trackhub1', 'trackhub1');

my $request = GET('http://127.0.0.1:3000/api/login');
$request->headers->authorization_basic($user, $pass);

my $response = $ua->request($request);
my $auth_token;
if ($response->is_success) {
  $auth_token = from_json($response->content)->{auth_token};
  print "Logged in [", $auth_token, "]\n" if $auth_token;
} else {
  die sprintf "Couldn't login, reason: %s [%d]", $response->content, $response->code;
}
