use strict;
use warnings;
use Test::More;
use Data::Dumper;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use HTTP::Request::Common;
use Catalyst::Test 'ElasticSearchDemo';
use ElasticSearchDemo::Controller::API;

# request return is HTTP::Response object
# Attributes:
#  _content
#  _rc
#  _headers
#  _msg
#  _request
# 
ok( !request('/api')->is_success, 'Request should not succeed' );

# ##########
# # Test initial gift list includes all the gifts
# #
# my @all_data = MyGifts::Model::Gifts->new->_get_data;
 
# my $response = get '/gifts';
 
# my @gifts = @{from_json($response)->{data}};
# is(@gifts, @all_data, "gift count match");
 
# for ( my $i=0 ; $i < @all_data; $i++ ) {
#   is(keys %{$gifts[$i]}, 2, "[$i] has 2 data fields");
#   is($gifts[$i]->{name}, $all_data[$i]->{name}, "[$i] name match");
#   is($gifts[$i]->{id}, $all_data[$i]->{id}, "[$i] id match");
# }

# my $response = get '/api';
# print $response;
# print Dumper(request('/api'));

done_testing();
