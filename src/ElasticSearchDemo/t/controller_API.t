use strict;
use warnings;
use Test::More;
use Data::Dumper;
use JSON;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use HTTP::Request::Common;
use JSON;
use Catalyst::Test 'ElasticSearchDemo';

use ElasticSearchDemo::Utils; # es_running
use ElasticSearchDemo::Indexer;

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    5 unless &ElasticSearchDemo::Utils::es_running();

  # index test data
  note 'Preparing data for test (indexing sample documents)';
  my $indexer = ElasticSearchDemo::Indexer->new(dir   => "$Bin/../../../docs/trackhub-schema/draft02/examples/",
						index => 'test',
						type  => 'trackhub',
						mapping => 'trackhub_mappings.json');
  $indexer->index();

  ok(my $response = request('/api/trackhub'), 'Request to /api/trackhub');
  ok($response->is_success, 'Request successful 2xx');
  is($response->content_type, 'application/json', 'JSON content type');
  my $content = from_json($response->content);
  map { like($content->{$_}, qr/api\/trackhub\/$_/, "contains correct resource URI") } 1 .. 2;
  
}



# #
# # TODO: check status codes
# #
# # request subroutine return is HTTP::Response object with attribs:
# #  _content
# #  _rc
# #  _headers
# #  _msg
# #  _request
# #
# my $response = request('/api');
# ok( !$response->is_success, 'Request with no credentials should not succeed' );

# my $content = from_json($response->content); 
# is( $content->{data}{error}, "Please specify username/password credentials", "Error response: no credentials");

# $response = request('/api?username=pippo;password=pluto');
# ok( !$response->is_success, 'Request with incorrect credentials should not succeed' );
# $content = from_json($response->content); 
# is( $content->{data}{error}, "Unauthorized", "Unsuccessful authentication message");

# $response = request('/api?username=test;password=test');
# ok( $response->is_success, 'Request with correct credentials should succeed' );
# $content = from_json($response->content); 
# is( $content->{data}{msg}, "Welcome user test", "Successful authentication message");


# this one gets the JSON string
# $response = get '/api';
# print ref $response, "\n";

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
# print Dumper(request('/api')), "\n\n";

done_testing();
