#!/usr/bin/env perl
# Copyright [2015-2017] EMBL-European Bioinformatics Institute
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
use Carp;
use Try::Tiny;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../../lib";
}

use Registry::Utils;
use Search::Elasticsearch;

my $index = 'test';
my $type = 'user';

die "Elasticsearch instance not running." 
  unless Registry::Utils::es_running();

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
$indices->create(index => $index,
#
# The following configuration generates an error:
#
# "Unknown param (mappings) in (create) request"
# even though the Search::Elasticsearch documentation refer
# to the official create index documentation which itself
# mention the mappings configuration option.
#
		 # mappings => {
		 # 	      $type => {
		 # 			"dynamic_templates" => [
		 # 						{
		 # 						 "test" => {
		 # 							    "match" => "*",
		 # 							    "match_mapping_type" => "string",
		 # 							    "mapping" => {
		 # 									  "type"  => "string",
		 # 									  "index" => "not_analyzed"
		 # 									 }
		 # 							   }
		 # 						}
		 # 					       ]
		 # 		       },
		 # 	     }
		);

#
# create mapping
#
# NOTE
# It's necessary to use dynamic templates in order to tell ES
# not to index any string field, otherwise fields like auth_key,
# which might be created with a random pattern containing lower
# and upper case characters, won't be suitable for exact matching
# and authentication won't find the user with the given field.
#
my $mapping = {
	       $type => {
			 "dynamic_templates" => [
						 {
						  "test" => {
							     "match" => "*",
							     "match_mapping_type" => "string",
							     "mapping" => {
									   "type"  => "string",
									   "index" => "not_analyzed"
									  }
							    }
						 }
						]
			},
	      };

$indices->put_mapping(index => $index,
		      type  => $type,
		      body  => $mapping);

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


