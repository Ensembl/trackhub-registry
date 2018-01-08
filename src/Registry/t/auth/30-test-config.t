#!/usr/bin/env perl
# Copyright [2015-2018] EMBL-European Bioinformatics Institute
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
use Test::Exception 0.31;
use Catalyst::Utils;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

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
