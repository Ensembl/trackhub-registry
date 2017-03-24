=head1 LICENSE

Copyright [2015-2017] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

Please email comments or questions to the Trackhub Registry help desk
at C<< <http://www.trackhubregistry.org/help> >>

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Indexer - Index mock user/track hub data

=head1 SYNOPSIS

    my $indexer = Registry::Indexer->new(dir => 'directory with track hub/mappings JSON',
                                         trackhub => {
                                           index   => 'track hub index name',
                                           type    => 'track hub type name',
                                           mapping => 'JSON file name with track hub mappings'
                                         },
                                         authentication => {
                                           index   => 'user index name',
                                           type    => 'user type name',
                                           mapping => 'JSON file name with authentication mappings'
                                         });
    $indexer->index_users; # can now run endpoints requiring authentication
    $indexer->index_trackhubs # can now run endpoints accessing track hub indexed data

=head1 DESCRIPTION

This module is used for preparing (mock) data for various tests. 

It has methods for indexing some fake users and track hubs so that tests can 
check correct responses from various endpoints requiring authentication and 
the availability of some data in the back end.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

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

=head1 METHODS

=head2 new

  Arg [dir]            : string (required)
                         The name of the directory where track hub example JSON docs 
                         and (track hub/authentication) mappings can be found. This
                         directory is expected to contain the files blueprint(1|2).json
                         containing examples of a JSON representation of the blueprint
                         track hub.
  Arg [trackhub]       : hashref (required)
                         Provides the index/type names and the mapping files used for
                         indexing track hubs                         
  Arg [authentication] : hashref (required) 
                         Provides the index/type names and the mapping files used for
                         indexing users for authentication related tests                     
  Example              :  my $indexer = Registry::Indexer->new(dir => 'trackhub-examples',
                                                               trackhub => {
                                                                 index   => 'test',
                                                                 type    => 'trackdb',
                                                                 mapping => 'trackhub_mappings.json'
                                                               },
                                                               authentication => {
                                                                 index   => 'test',
                                                                 type    => 'user',
                                                                 mapping => 'authentication_mappings.json'
                                                               });
  Description          : Creates a new Indexer object. After creation, the track hub and user indices 
                         will be available. 
  Returntype           : Registry::Indexer
  Exceptions           : none
  Caller               : general
  Status               : stable

=cut

sub new {
  my ($caller, %args) = @_;

  my ($dir, $trackhub_settings, $auth_settings) = ($args{dir}, $args{trackhub}, $args{authentication});
  defined $dir or croak "Undefined directory arg";
  defined $trackhub_settings and defined $auth_settings or
    croak "Undefined trackhub and/or authentication settings";

  my $class = ref($caller) || $caller;
  # my $self = bless({ index => $index, type => $type, mapping => "$dir/$mapping" }, $class);
  my $self = bless({ trackhub => $trackhub_settings, auth => $auth_settings }, $class);
  $self->{trackhub}{mapping} = "$dir/" . $self->{trackhub}{mapping};
  $self->{auth}{mapping} = "$dir/" . $self->{auth}{mapping};

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

  # add example users, name should match the owners of the above docs
  $self->{users} = [
		    {		# the administrator
		     id       => 1,
		     fullname => "Administrator",
		     email    => "avullo\@ebi.ac.uk",
		     password => "admin",
		     roles    => ["admin", "user"],
		     username => "admin",
		    },
		    {		# a first trackhub content provider
		     id          => 2,
		     first_name  => "Track",
		     last_name   => "Hub1",
		     affiliation => "EMBL-EBI",
		     email       => "trackhub1\@ebi.ac.uk",
		     fullname    => "TrackHub1",
		     password    => "trackhub1",
		     roles       => ["user"],
		     username    => "trackhub1",
		    },
		    {		# a second trackhub content provider
		     id          => 3,
		     first_name  => "Track",
		     last_name   => "Hub2",
		     affiliation => "UCSC",
		     email       => "trackhub2\@ucsc.edu",
		     fullname    => "TrackHub2",
		     password    => "trackhub2",
		     roles       => ["user"],
		     username    => "trackhub2",
		    },
		    {		# a third trackhub content provider
		     id          => 4,
		     first_name  => "Track",
		     last_name   => "Hub3",
		     affiliation => "Sanger",
		     email       => "trackhub3\@sanger.ac.uk",
		     fullname    => "TrackHub3",
		     password    => "trackhub3",
		     roles       => ["user"],
		     username    => "trackhub3",
		    },
		   ];

  # Module is used for testing, which assumes there's
  # an ES instance running on the same host.
  # We don't pass arguments to get the default (localhost)
  $self->{es} = Registry::Model::Search->new();
  $self->create_indices();

  return $self;
}

=head2 create_indices

  Arg [1]    : none
  Example    : $indexer->create_indices
  Description: Create indices for track hubs and users
  Returntype : none
  Exceptions : Thrown is trackhub/user index,type,parameters are missing,
               Elasticsearch client throws some error, or track hub/authentication
               mapping cannot be created.
  Caller     : general
  Status     : stable

=cut

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

  #
  # create the authentication/authorisation mapping
  #
  # Note: we might/might not store user data on the same index as that of the trackhubs
  #       do not delete/recreate the index if it exists
  ($index, $type, $mapping) = ($self->{auth}{index}, $self->{auth}{type}, $self->{auth}{mapping});
  defined $index && defined $type && defined $mapping or
    croak "Missing trackhub parameters (index|type|mapping)";
  unless ($indices->exists(index => $index)) {
    carp "Creating index $index";
    $indices->create(index => $index);  
  }

  $indices->put_mapping(index => $index,
			type  => $type,
			body  => from_json(&Registry::Utils::slurp_file($mapping)));
  $mapping_json = $indices->get_mapping(index => $index, type  => $type);
  exists $mapping_json->{$index}{mappings}{$type} or croak "Authentication/authorisation mapping not created";
  carp "Authentication/authorisation mapping created";

}

=head2 index_trackhubs

  Arg [1]    : none
  Example    : $indexer->index_trackhubs
  Description: Index the example documents
               After invoked, four documents will be available: two belonging to user 
               trackhub1 (blueprint(1|2), one to user trackhub2 (blueprint1) and one
               to trackhub3 (blueprint2).
  Returntype : none
  Exceptions : Thrown if Elasticsearch client fails to index one of the documents
  Caller     : general
  Status     : stable

=cut

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

=head2 index_users

  Arg [1]    : none
  Example    : $indexer->index_users
  Description: Index the example users for the authentication/authorisation mechanism.
               After invoked, four users will be available: one with admin role, and
               three for testing track hub submissions and data retrieval.
               Check the source code for the constructor for details about these users,
               e.g. username/password
  Returntype : none
  Exceptions : Thrown if Elasticsearch client fails to index one of the mock users
  Caller     : general
  Status     : stable

=cut

sub index_users {
  my $self = shift;

  foreach my $user (@{$self->{users}}) {
    my $id = $user->{id};
    carp "Indexing user $id ($user->{fullname}) document";
    $self->{es}->index(index   => $self->{auth}{index},
		       type    => $self->{auth}{type},
		       id      => $id,
		       body    => $user);
  }

  carp "Flushing recent changes";
  $self->{es}->indices->refresh(index => $self->{auth}{index});
}

=head2 delete

  Arg [1]    : none
  Example    : $indexer->delete
  Description: Delete track hub/user indices, with all their content within.
  Returntype : none
  Exceptions : Thrown if Elasticsearch client fails to delete one of the indices
  Caller     : general
  Status     : Stable

=cut

sub delete {
  my $self = shift;

  $self->{es}->indices->delete(index => $self->{trackhub}{index});
  $self->{es}->indices->delete(index => $self->{auth}{index})
    if $self->{auth}{index} ne $self->{trackhub}{index};
}

=head2 docs

  Arg [1]    : none
  Example    : my @docs = @{$indexer->docs};
  Description: Get the list of example documents.
               Each array item is a hashref with id, file and owner attributes
  Returntype : arrayref
  Exceptions : none
  Caller     : general
  Status     : stable

=cut

sub docs {
  my $self = shift;

  return $self->{docs};
}

=head2 get_user_data

  Arg [1]    : none
  Example    : my @users = @{$indexer->get_user_data};
  Description: Returns a list of items, each one representing information about
               a particular example user which can authenticate and submit track hubs.
  Returntype : arrayref
  Exceptions : none
  Caller     : general
  Status     : stable

=cut

sub get_user_data {
  my $self = shift;

  return $self->{users};
}

1;
