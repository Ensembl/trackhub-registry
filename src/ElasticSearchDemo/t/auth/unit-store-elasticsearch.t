#!/usr/bin/env perl 

use strict;
use warnings;
use FindBin 1.49;
use lib "$FindBin::Bin/lib";

use Test::More 0.98;

BEGIN {
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
note $session_data;

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
