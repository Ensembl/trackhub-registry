use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use LWP;
use JSON;
use Data::Dumper;

use_ok 'ElasticSearchDemo::Model::ElasticSearch';

my $es = ElasticSearchDemo::Model::ElasticSearch->new();

isa_ok($es, 'ElasticSearchDemo::Model::ElasticSearch');
is($es->nodes, 'localhost:9200', 'Correct default nodes');

SKIP: {
  skip "Launch an elasticsearch instance for the tests to run fully",
    8 unless get('http://localhost:9200')->is_success;

  my $es = ElasticSearchDemo::Model::ElasticSearch->new();

  #
  # create the index (test)
  #
  my ($index, $type) = ('test', 'trackhub');
  
  #
  # delete the index if it exists
  #
  $es->indices->delete(index => $index) and note "Deleting index $index"
    if $es->indices->exists(index => $index);
    
  # recreate the index
  note "Creating index $index";
  $es->indices->create(index => $index); 
  ok($es->indices->exists(index => $index), "Index created");
  
  #
  # create the mapping (trackhub)
  #
  my $mapping_json = from_json(&slurp_file("$Bin/trackhub_mappings.json"));
  
  note "Creating trackhub mapping";
  $es->indices->put_mapping(index => $index,
			    type  => $type,
			    body  => $mapping_json);
  $mapping_json = $es->indices->get_mapping(index => $index,
					    type  => $type);
  ok(exists $mapping_json->{$index}{mappings}{$type}, "Mapping created");

  #
  # add example trackhub documents
  #
  # NOTE
  # Adding version [1-2].1 as in original [1-2]
  # search doesn't work as it's not indexing
  # the fields
  #
  my $id = 1;
  my $bp = "$Bin/blueprint1.1.json";
  note "Indexing document $bp";
  $es->index(index   => $index,
	     type    => $type,
	     id      => $id++,
	     body    => from_json(&slurp_file($bp)));
	     
  $bp = "$Bin/blueprint2.1.json";
  note "Indexing document $bp";
  $es->index(index   => $index,
	     type    => $type,
	     id      => $id++,
	     body    => from_json(&slurp_file($bp)));

  # The refresh() method refreshes the specified indices (or all indices), 
  # allowing recent changes to become visible to search. 
  # This process normally happens automatically once every second by default.
  note "Flushing recent changes";
  $es->indices->refresh(index => $index);

  #
  # Test getting all documents
  #
  # no args default to get all docs
  #
  my $docs = $es->query();
  is(scalar @{$docs->{hits}{hits}}, 2, "Doc counts when requesting all documents match");

  #
  # Test getting documents by IDs
  #
  # missing args throws exception
  my %args;   
  throws_ok { $es->find(%args) }
    qr/Missing/, "Fetch doc without required arguments";
  $args{index} = 'test';
  $args{id} = 1;
  throws_ok { $es->find(%args) }
    qr/Missing/, "Fetch doc without required arguments";

  # getting existing documents
  $args{id} = 1;
  $args{type} = 'trackhub';
  my $doc = $es->find(%args);
  is($doc->{data}[0]{name}, "bpDnaseRegionsC0010K46DNaseEBI", "Fetch correct document");
  
  $args{id} = 2;
  $doc = $es->find(%args);
  is(scalar @{$doc->{data}}, 4, "Fetch correct document");

  # getting document by non-existant ID
  $args{id} = 3;
  throws_ok { $es->find(%args) }
    qr/Missing/, "Request document by incorrect ID"
}

done_testing();

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

sub get {
  my ($href) = @_;

  my $req = HTTP::Request->new( GET => $href );

  my $ua = LWP::UserAgent->new;
  my $response = $ua->request($req);

  return $response;
  # my @ret = ( $response->message, $response->code);

  # return wantarray ? @ret : \@ret;  
}
