#!/usr/bin/env perl

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
