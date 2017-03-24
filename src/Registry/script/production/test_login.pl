#!/usr/bin/env perl
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

use Test::More;
# BEGIN { plan tests => 8, onfail => sub { print "Some test failed\n" } }

use WWW::Mechanize;
use Test::WWW::Mechanize;

@ARGV == 2 or die "Usage: test_login.pl <user> <pass>\n";

my $server = 'http://127.0.0.1:5000';
my ($user, $pass) = ($ARGV[0], $ARGV[1]);

# my $mech = Test::WWW::Mechanize->new;
# $mech->get_ok($server . '/login');
# $mech->submit_form_ok( {
# 			form_number => 2,
# 			fields      => {
# 					username => $user,
# 					password => $pass
# 				       },
# 		       }, 'Submit login'
# 		     );

# $mech->content_contains('Logout', 'Logged in');
# $mech->content_contains('AAAA', 'Fake content');
# $mech->content_contains('Your track collections', 'List of track hubs');
# $mech->link_content_like($server . "/user/$user/profile", qr/Profile for user/, 'Can access profile');
# $mech->link_content_like($server . "/user/$user/list_trackhubs", qr/Your track collections/, 'Can access track hub list');
# $mech->links_ok($server . '/logout', 'Logged out');

my $mech = WWW::Mechanize->new;
$mech->get($server . '/login');
ok($mech->success, 'Can access login page');
$mech->submit_form(form_number => 2,
		   fields      => {
				   username => $user,
				   password => $pass
				  });
like($mech->content, qr/Logout/, 'Logged in');

for (1 .. 5) {
  like($mech->content, qr/Your track collections/, 'List of track hubs');
  $mech->follow_link(text => 'Profile');
  like($mech->content, qr/Profile for user/, 'Can access profile');
  $mech->follow_link(text => 'My track collections');
}
$mech->follow_link( url => $server . '/logout');
ok($mech->success, 'Logged out');

done_testing();

