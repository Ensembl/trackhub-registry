use strict;
use warnings;
use Test::More;


use Catalyst::Test 'ElasticSearchDemo';
use ElasticSearchDemo::Controller::User;

ok( request('/user')->is_success, 'Request should succeed' );
done_testing();
