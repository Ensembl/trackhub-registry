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
use LWP;
use JSON;

use Registry::Utils;
use Registry::Model::Search;
use Registry::TrackHub::TrackDB;

sub new {
  my ($caller, %args) = @_;

  my ($dir, $index, $trackhub_settings, $auth_settings) = ($args{dir}, $args{index}, $args{trackhub}, $args{authentication});
  defined $dir or croak "Undefined directory arg";
  defined $index or croak "Undefined index arg";
  defined $trackhub_settings and defined $auth_settings or
    croak "Undefined trackhub and/or authentication settings";

  my $class = ref($caller) || $caller;
  # my $self = bless({ index => $index, type => $type, mapping => "$dir/$mapping" }, $class);
  my $self = bless({ index => $index, trackhub => $trackhub_settings, auth => $auth_settings }, $class);
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
  $self->create_index();

  return $self;
}

#
# Create index, mapping 
#
sub create_index {
  my $self = shift;

  my $index = $self->{index};
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
  exists $self->{trackhub}{type} && exists $self->{trackhub}{mapping} or
    croak "Missing trackhub parameters (type|mapping)";
  $indices->put_mapping(index => $index,
			type  => $self->{trackhub}{type},
			body  => from_json(&Registry::Utils::slurp_file($self->{trackhub}{mapping})));
  my $mapping_json = $indices->get_mapping(index => $index,
					   type  => $self->{trackhub}{type});
  exists $mapping_json->{$index}{mappings}{trackhub} or croak "TrackHub mapping not created";
  carp "TrackHub mapping created";

  #
  # create the authentication/authorisation mapping
  #
  exists $self->{auth}{type} && exists $self->{auth}{mapping} or
    croak "Missing authentication/authorization parameters (type|mapping)";
  $indices->put_mapping(index => $index,
			type  => $self->{auth}{type},
			body  => from_json(&Registry::Utils::slurp_file($self->{auth}{mapping})));
  $mapping_json = $indices->get_mapping(index => $index,
					type  => $self->{auth}{type});
  exists $mapping_json->{$index}{mappings}{user} or croak "Authentication/authorisation mapping not created";
  carp "Authentication/authorisation mapping created";

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
    $self->{es}->index(index   => $self->{index},
		       type    => $self->{trackhub}{type},
		       id      => $doc->{id},
		       body    => $doc_data);
  }

  # The refresh() method refreshes the specified indices (or all indices), 
  # allowing recent changes to become visible to search. 
  # This process normally happens automatically once every second by default.
  carp "Flushing recent changes";
  $self->{es}->indices->refresh(index => $self->{index});
}

#
# index the example users for the authentication/authorisation mechanism=
#
sub index_users {
  my $self = shift;

  foreach my $user (@{$self->{users}}) {
    my $id = $user->{id};
    carp "Indexing user $id ($user->{fullname}) document";
    $self->{es}->index(index   => $self->{index},
		       type    => $self->{auth}{type},
		       id      => $id,
		       body    => $user);
  }

  carp "Flushing recent changes";
  $self->{es}->indices->refresh(index => $self->{index});
}


#
# delete everything created 
#
sub delete {
  my $self = shift;

  $self->{es}->indices->delete(index => $self->{index});
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
