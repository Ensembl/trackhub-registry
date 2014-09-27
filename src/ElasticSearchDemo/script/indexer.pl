#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  # use RestHelper;
  # $ENV{CATALYST_CONFIG} = "$Bin/../ensembl_rest_testing.conf";
  # $ENV{ENS_REST_LOG4PERL} = "$Bin/../log4perl_testing.conf";
}

use JSON;
use Data::Dumper;

use URI::Escape;
use LWP;

use ElasticSearchDemo::Model::ElasticSearch;
# use Search::Elasticsearch;

my $es = ElasticSearchDemo::Model::ElasticSearch->new();
# my $es = Search::Elasticsearch->new();
defined $es or die "Unable to get ES instance.";

my ($index, $type) = ('test', 'trackhub');
my $indices = $es->indices;

# delete the index if it exists
$indices->delete(index => $index) and print "Deleting index $index\n"
  if $indices->exists(index => $index);

# recreate the index
print "Creating index $index. ";
$indices->create(index => $index); # , type => 'trackhub', body => {});
print "Done.\n";

# create the mapping
my $mapping_json = from_json(&slurp_file('trackhub_mappings.json'));

print "Creating trackhub mapping. ";
$es->indices->put_mapping(index => $index,
			  type  => $type,
			  body  => $mapping_json);
print "Done.\n";

my $id = 1;
my $bp = 'blueprint1.1.json';
print "Indexing document $bp. ";
$es->index(index   => $index,
	   type    => $type,
	   id      => $id++,
	   body    => from_json(&slurp_file($bp)));
print "Done.\n";
	     
$bp = 'blueprint2.1.json';
print "Indexing document $bp. ";
$es->index(index   => $index,
	   type    => $type,
	   id      => $id++,
	   body    => from_json(&slurp_file($bp)));
print "Done.\n";

# The refresh() method refreshes the specified indices (or all indices), 
# allowing recent changes to become visible to search. 
# This process normally happens automatically once every second by default.

# NOTE: doesn't work, search cannot find anything
$indices->refresh(index => $index);

# Test search: alignment_software:bwa
my $results = $es->search(index => $index,
			  type  => $type,
			  body  => { query => { term => { alignment_software => 'bwa' } } });

printf "Search for alignment_software:bwa returned %d docs.\n", $results->{hits}{total};
# body  => { query => { match => { alignment_software => 'bwa'} } });
# q => 'alignment_software:bwa');
# params => { q => 'alignment_software:bwa' });

# print Dumper($results);

sub slurp_file {
  my $file = shift;

  my $string;
  {
    local $/=undef;
    open FILE, "<$file" or die "Couldn't open file: $!";
    $string = <FILE>;
    close FILE;
  }
  
  return $string;
}

#################
# $es->index(index   => $index,
# 	   type    => $type,
# 	   id      => 1,
# 	   body    => {
# 		       title  => 'pippo',
# 		       author => 'pluto'
# 		       });
# # my $query = { query => { term => { title => 'pippo' } } };
# # my $query = { query => { filtered => { filter => { term => { title => 'pippo' }}}}};
# my $query;
# # even the empty query returns no result!!!
# my $results = $es->search(); 
# # my $results = $es->search(index => $index,
# # 			  type  => $type);
# # 			  body  => $query); # to_json($query));
# print Dumper($results);

# my $ua = user_agent();
# my $ret = get($ua, "http://localhost:9200/test/trackhub/_search?q:title=pippo");
# print Dumper($ret);
# exit;
#################


# sub user_agent {
#   return LWP::UserAgent->new;
# }

# sub get {
#   my ($ua, $href) = @_;

#   my $req = HTTP::Request->new( GET => $href );

#   my $response = $ua->request($req);
#   return $response;
# }
