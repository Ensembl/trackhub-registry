#!/usr/bin/env perl 

use Test::More 0.98 tests => 2;

BEGIN {
  use_ok( 'Catalyst::Authentication::Store::ElasticSearch' );
  use_ok( 'Catalyst::Authentication::Store::ElasticSearch::User' );
}

diag( "Testing Catalyst::Authentication::Store::ElasticSearch $Catalyst::Authentication::Store::ElasticSearch::VERSION, Perl $], $^X" );
