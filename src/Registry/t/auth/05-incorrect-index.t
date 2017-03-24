#!perl
# Copyright [2015-2017] EMBL-European Bioinformatics Institute
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
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";

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
			index  => 'missing',
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
  is( $res->content, 'Index does not exist', 'correct diagnostic for non existant index');
}

done_testing;
