#!/usr/bin/env perl
# Copyright [2015-2016] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;
use FindBin 1.49;
use lib "$FindBin::Bin/lib";
use Test::More 0.98;

BEGIN {
	plan( skip_all => 'ElasticSearch is not used to store User info anymore' );
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
                usersauthkey => {
                    credential => {
                        class          => "Password",
                        password_type  => 'none'
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

use String::Random;
use Catalyst::Test 'TestApp';

#
# test user login and get authentication token
#
my $auth_token = String::Random->new->randpattern("s" x 64);
ok( my $res = request("http://localhost/user_login?username=test&password=test&auth_token=$auth_token&detach=get_auth_key"), 'request ok' );
is( $res->content, $auth_token, 'auth token' );

#
# test user authentication with auth key
#
# 1. no auth key
ok( $res = request("http://localhost/auth_key_access?username=test"), 'request ok' );
is( $res->content, 'user not key authenticated', 'user not authenticated with no auth key' );

# 2. incorrect auth key
ok( $res = request("http://localhost/auth_key_access?username=test&auth_key=aaa"), 'request ok' );
is( $res->content, 'user not key authenticated', 'user not authenticated with incorrect auth key' );

# 3. correct auth key
ok( $res = request("http://localhost/auth_key_access?username=test&auth_key=$auth_token"), 'request ok' );
is( $res->content, 'test authenticated with key', 'user authenticated with auth key' );

done_testing;
