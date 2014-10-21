#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Try::Tiny;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../../lib";
}

use ElasticSearchDemo::Utils;
use Search::Elasticsearch;

my $index = 'test';
my $type = 'user';

die "Elasticsearch instance not running." 
  unless ElasticSearchDemo::Utils::es_running();

# Firstly, delete the index
my $es = Search::Elasticsearch->new();
my $indices = $es->indices;

$indices->delete(index => $index) and carp "Deleting index $index"
  if $indices->exists(index => $index);

# try {
#     $db->delete();
# } catch {
# };

# Now, create the index again
carp "Creating index $index";
$indices->create(index => $index);

# Get the data for each user document to be created, and create it.
my $id = 1;
foreach my $user_doc (get_doc_data()) {
  carp sprintf "Indexing user %s", $user_doc->{fullname};
  $es->index(index => $index,
	     type  => $type,
	     id    => $id++,
	     body => $user_doc);
}

carp "Flushing recent changes";
$es->indices->refresh(index => $index);

sub get_doc_data {
  return 
    (
     {
      fullname => "Test User",
      password => "test",
      roles    => ["admin", "user"],
      username => "test",
     },
     {
      fullname => "Test User 2",
      password => "test2",
      roles    => ["user"],
      username => "test2",
     },
    );
}


