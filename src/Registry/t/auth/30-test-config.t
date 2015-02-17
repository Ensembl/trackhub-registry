#!/usr/bin/env perl

use strict;
use warnings;
use FindBin 1.49;
use lib "$FindBin::Bin/lib";

use Test::More 0.98;
use Test::Exception 0.31;
use Catalyst::Utils;

my $good_config = 
  {
   index => 'test',
   type  => 'user'
  };

use_ok('Catalyst::Authentication::Store::ElasticSearch::User');

foreach my $keyname ( sort keys %$good_config) {
  my $bad_config = { %$good_config };
  delete $bad_config->{$keyname};
    
  throws_ok (
	     sub {
	       my $test_user = Catalyst::Authentication::Store::ElasticSearch::User->new($bad_config, undef);
	     },
	     'Catalyst::Exception',
	     $keyname.' missing throws an exception'
	    );
}

my $bad_config = {
		  %$good_config,
		  index => 'incorrect index',
		 };

throws_ok (
	   sub {
	     my $test_user = Catalyst::Authentication::Store::ElasticSearch::User->new($bad_config, undef),
	   },
	   'Catalyst::Exception',
	   'incorrect user configuration throws an exception',
	  );

done_testing;
