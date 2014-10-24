#!/usr/bin/env perl

use strict;
use warnings;
use FindBin 1.49;
use Test::More 0.98;

use lib "$FindBin::Bin/lib";

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
                        nodes  => 'localhost:65530', # Note - hopefully there's nothing listening on this port.
			index  => 'test',
			type   => 'user'
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
  is( $res->content, 'Elasticsearch instance not available', 'correct diagnostic for ElasticSearch missing');
}

done_testing;
