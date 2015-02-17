use strict;
use warnings;
use Test::More;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use Catalyst::Test 'ElasticSearchDemo';
use ElasticSearchDemo::Controller::User;

ok( request('/user')->is_success, 'Request should succeed' );
done_testing();
