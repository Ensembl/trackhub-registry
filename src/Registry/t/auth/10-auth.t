#!/usr/bin/env perl

use strict;
use warnings;
use FindBin 1.49;
use lib "$FindBin::Bin/lib";
use Data::Dumper;

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
                        class => 'ElasticSearch',
			index => 'test',
			type  => 'user'
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
  is( $res->content, 'test logged in', 'user logged in ok' );
}

# invalid user
{
  ok( my $res = request('http://localhost/user_login?username=foo&password=bar'), 'request ok' );
  is( $res->content, 'not logged in', 'user not logged in ok' );
}

# log the user out
{
  ok( my $res = request('http://localhost/user_logout'), 'request ok' );
  is( $res->content, 'logged out', 'user logged out ok' );
}

done_testing;
