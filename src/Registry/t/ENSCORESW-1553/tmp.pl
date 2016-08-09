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

use JSON;
use Data::Dumper;
# use utf8;
use Encode qw(encode_utf8); 
use Search::Elasticsearch;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use Registry::TrackHub;


my $URL = 'http://www.ebi.ac.uk/~tapanari/data/test/SRP022925/hub.txt';
my $trackhub = Registry::TrackHub->new(url => $URL, permissive => 1);
my $doc = 
    {
     version => 'v1.0',
     hub     => {
		 name       => $trackhub->hub,
		 shortLabel => $trackhub->shortLabel,
		 longLabel  => $trackhub->longLabel,
		 url        => $trackhub->url
		}
    };

my $json = to_json($doc, { pretty => 1 });
# print encode_utf8($doc->{hub}{longLabel}), "\n";
print $json, "\n";
print Dumper from_json($json);
my $es = Search::Elasticsearch->new();
# $es->delete(index => 'test', 
# 	   type  => 'trackdb',  
# 	   id    => 'test');
$es->index(index => 'test', 
	   type  => 'trackdb',  
	   id    => 'test',
	   body  => $json);
my $d = $es->get(index => 'test',
		 type  => 'trackdb',
		 id    => 'test');
print Dumper $d;
