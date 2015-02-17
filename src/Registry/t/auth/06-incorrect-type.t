#!perl

use strict;
use warnings;
use FindBin 1.49;
use lib "$FindBin::Bin/lib";


use Test::More 0.98;

BEGIN {
    $ENV{TESTAPP_CONFIG} = {
        name => 'TestApp',
        authentication => {
            default_realm => "users",
            realms => {
                users => {
                    credential => {
                        class          => "Password",
                        password_field => 'password',
                        password_type  => 'clear'
                    },
                    store => {
                        class  => 'ElasticSearch',
			index  => 'test',
			type   => 'missing'
                    },
                },
            },
        },
    };

    $ENV{TESTAPP_PLUGINS} = [
        qw/Authentication/
    ];
}

use Catalyst::Test 'TestApp';

# log a user in
{
    ok( my $res = request('http://localhost/user_login?username=test&password=test'), 'request ok' );
    is( $res->content, 'Type does not exist', 'Correct diagnostic for non existant user type');
}

done_testing;
