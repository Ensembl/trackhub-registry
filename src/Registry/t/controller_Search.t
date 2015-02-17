use strict;
use warnings;
use Test::More;


use Catalyst::Test 'Registry';
use Registry::Controller::Search;

ok( request('/search')->is_success, 'Request should succeed' );
done_testing();
