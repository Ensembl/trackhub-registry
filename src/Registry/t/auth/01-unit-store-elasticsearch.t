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
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";

  use_ok( 'Catalyst::Authentication::Store::ElasticSearch' );
  use_ok( 'Catalyst::Authentication::Store::ElasticSearch::User' );
}



my $config = {
	      nodex => 'localhost:9200',
	      index => 'test',
	      type  => 'user',
	     };

my $store_es = Catalyst::Authentication::Store::ElasticSearch->new($config);
isa_ok($store_es, 'Catalyst::Authentication::Store::ElasticSearch');

# sub find_user

my $good_user = $store_es->find_user({ username => 'test' });
ok($good_user, 'User correctly found');

isa_ok($good_user, 'Catalyst::Authentication::Store::ElasticSearch::User');
my $missing_user = $store_es->find_user({ username => 'testmissing' });
ok(!defined $missing_user, 'Missing user not found');

# sub for_session

my $session_data = $store_es->for_session(undef, $good_user);
is(ref $session_data, '', 'Got a scalar back from for_session');

# sub from_session
my $good_user2 = $store_es->from_session(undef, $session_data);

is($good_user2->id, $good_user->id, 'User from session id matches original');

# sub user_supports

my $supports = $store_es->user_supports();

ok($supports->{roles}, 'Store supports roles');
ok($supports->{session}, 'Store supports session');

# AUTOLOAD

is($good_user->username, 'test', 'AUTOLOAD for username field works');
is($good_user->missing, undef, 'AUTOLOAD for missing field returns undef');


done_testing;
