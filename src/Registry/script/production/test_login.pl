#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
# BEGIN { plan tests => 8, onfail => sub { print "Some test failed\n" } }

use WWW::Mechanize;
use Test::WWW::Mechanize;

@ARGV == 2 or die "Usage: test_login.pl <user> <pass>\n";

my $server = 'https://trackhubregistry.org';
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

