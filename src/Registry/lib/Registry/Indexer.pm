=head1 LICENSE

Copyright [2015-2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Registry::Indexer;

use strict;
use warnings;

#
# TODO
# Have to use this until I implement with Moose
#
BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/..";
}

use Carp;
use JSON;

use Registry::Utils;
use Registry::Model::Search;

sub new {
  my ($caller, %args) = @_;

  my ($dir, $trackhub_settings) = ($args{dir}, $args{trackhub});
  defined $dir or croak "Undefined directory arg";
  defined $trackhub_settings or
    croak "Undefined trackhub settings";

  my $class = ref($caller) || $caller;
  my $self = bless({ trackhub => $trackhub_settings}, $class);
  $self->{trackhub}{mapping} = "$dir/" . $self->{trackhub}{mapping};

  #
  # Add example trackhub documents
  # Considering multiple copies of the same
  # documents but assigning them to different
  # owners
  #
  $self->{docs} = [
		      {
		       id    => 1,
		       file  => "$dir/blueprint1.json",
		       owner => 'trackhub1'
		      },
		      {
		       id    => 2,
		       file  => "$dir/blueprint2.json",
		       owner => 'trackhub1'
		      },
		      {
		       id    => 3,
		       file  => "$dir/blueprint1.json",
		       owner => 'trackhub2'
		      },
		      {
		       id    => 4,
		       file  => "$dir/blueprint2.json",
		       owner => 'trackhub3'
		      },
		     ];


  # Module is used for testing, which assumes there's
  # an ES instance running on the same host.
  # We don't pass arguments to get the default (localhost)
  $self->{es} = Registry::Model::Search->new();
  $self->create_indices();

  return $self;
}

#
# Create indices, mapping 
#
sub create_indices {
  my $self = shift;

  # create trackhub index/mapping
  my ($index, $type, $mapping) = ($self->{trackhub}{index}, $self->{trackhub}{type}, $self->{trackhub}{mapping});
  defined $index && defined $type && defined $mapping or
    croak "Missing trackhub parameters (index|type|mapping)";

  my $indices = $self->{es}->indices;
  #
  # create the index 
  #
  # delete the index if it exists
  $indices->delete(index => $index) and carp "Deleting index $index"
    if $indices->exists(index => $index);
    
  # recreate the index
  carp "Creating index $index";
  $indices->create(index => $index); 
    #
  # create the trackhub mapping
  #
  $indices->put_mapping(index => $index,
			type  => $type,
			body  => from_json(&Registry::Utils::slurp_file($mapping)));
  my $mapping_json = $indices->get_mapping(index => $index, type  => $type);
  exists $mapping_json->{$index}{mappings}{$type} or croak "TrackHub mapping not created";
  carp "TrackHub mapping created";

}
#
# index the example documents 
#
sub index_trackhubs {
  my $self = shift;
  #
  # add example trackhub documents
  #
  foreach my $doc (@{$self->{docs}}) {
    carp "Indexing trackhub document $doc->{file}";
    -e $doc->{file} or 
      croak "$doc->{file} does not exist or it's not accessible";
    
    # load doc from JSON, add owner, set version and status
    my $doc_data = from_json(&Registry::Utils::slurp_file($doc->{file}));
    $doc_data->{owner} = $doc->{owner};
    $doc_data->{version} = 'v1.0';
    $doc_data->{created} = time();
    $doc_data->{status}{message} = 'Unknown';

    # index doc
    $self->{es}->index(index   => $self->{trackhub}{index},
		       type    => $self->{trackhub}{type},
		       id      => $doc->{id},
		       body    => $doc_data);
  }

  # The refresh() method refreshes the specified indices (or all indices), 
  # allowing recent changes to become visible to search. 
  # This process normally happens automatically once every second by default.
  carp "Flushing recent changes";
  $self->{es}->indices->refresh(index => $self->{trackhub}{index});
}

#
# index the example users for the authentication/authorisation mechanism=
# deprecated
sub index_users {}

#
# delete everything created 
#
sub delete {
  my $self = shift;

  $self->{es}->indices->delete(index => $self->{trackhub}{index});
}

#
# get the list of doc data
#
sub docs {
  my $self = shift;

  return $self->{docs};
}

#
# return a list of documents representing users
# that can authenticate and be authorised
#
sub get_user_data {
  my $self = shift;

  return $self->{users};
}

1;
