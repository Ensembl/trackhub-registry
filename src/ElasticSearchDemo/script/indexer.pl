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
use ElasticSearchDemo::Model::ElasticSearch;
my $es = ElasticSearchDemo::Model::ElasticSearch->new();
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
