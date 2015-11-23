use strict;
use warnings;

use JSON;
use HTTP::Request::Common;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
my $server = 'http://127.0.0.1:3000';
my $HUB_URL = 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt';
my ($user, $pass, $auth_token) = ('trackhub1', 'trackhub1');

$auth_token = login($server, $user, $pass);

my $request = POST("$server/api/trackhub",
		   'Content-type' => 'application/json',
		   'Content'      => to_json({ url => $HUB_URL,
					       assemblies => {
							      araTha1 => 'GCA_000001735.1',
							      ricCom1 => 'GCA_000151685.2',
							      braRap1 => 'GCA_000309985.1'}}));
$request->headers->header(user       => $user);
$request->headers->header(auth_token => $auth_token);
my $response = $ua->request($request);
if ($response->is_success) {
  print "I have registered hub at $HUB_URL\n";
} else {
  die sprintf "Couldn't register hub at $HUB_URL: %s [%d]", $response->content, $response->code;
} 

logout($server, $user, $auth_token);

sub login {
  my ($server, $user, $pass) = @_;

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

  return $auth_token;
}

sub logout {
  my ($server, $user, $auth_token) = @_;

  my $request = GET("$server/api/logout");
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $auth_token);

  my $response = $ua->request($request);
  if ($response->is_success) {
    print "Logged out\n";
  } else {
    die sprintf "Unable to logout: %s [%d]", $response->content, $response->code;
  } 
}
