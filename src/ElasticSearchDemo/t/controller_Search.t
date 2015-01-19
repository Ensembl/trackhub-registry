use strict;
use warnings;
use Test::More;


use Catalyst::Test 'ElasticSearchDemo';
use ElasticSearchDemo::Controller::Search;

ok( request('/search')->is_success, 'Request should succeed' );
done_testing();
