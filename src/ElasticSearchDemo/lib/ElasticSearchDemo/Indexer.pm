package ElasticSearchDemo::Indexer;

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

use ElasticSearchDemo::Utils;
use ElasticSearchDemo::Model::ElasticSearch;

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
  # NOTE
  # Adding version [1-2].1 as in original [1-2]
  # search doesn't work as it's not indexing
  # the fields
  #
  $self->{docs} = [
		      {
		       id    => 1,
		       file  => "$dir/blueprint1.1.json",
		       owner => 'trackhub1'
		      },
		      {
		       id    => 2,
		       file  => "$dir/blueprint2.1.json",
		       owner => 'trackhub1'
		      },
		      {
		       id    => 3,
		       file  => "$dir/blueprint1.1.json",
		       owner => 'trackhub2'
		      },
		      {
		       id    => 4,
		       file  => "$dir/blueprint2.1.json",
		       owner => 'trackhub3'
		      },
		     ];

  # add example users, name should match the owners of the above docs
  $self->{users} = [
		    {		# the administrator
		     fullname => "Administrator",
		     password => "admin",
		     roles    => ["admin", "user"],
		     username => "admin",
		    },
		    {		# a first trackhub content provider
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
		     first_name  => "Track",
		     last_name   => "Hub3",
		     affiliation => "Sanger",
		     email       => "trackhub2\@sanger.ac.uk",
		     fullname    => "TrackHub3",
		     password    => "trackhub3",
		     roles       => ["user"],
		     username    => "trackhub3",
		    },
		   ];

  &ElasticSearchDemo::Utils::es_running() or
    croak "ElasticSearch instance not available";

  $self->{es} = ElasticSearchDemo::Model::ElasticSearch->new();
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
			body  => from_json(&ElasticSearchDemo::Utils::slurp_file($self->{trackhub}{mapping})));
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
			body  => from_json(&ElasticSearchDemo::Utils::slurp_file($self->{auth}{mapping})));
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
    
    # load doc from JSON, add owner
    my $doc_data = from_json(&ElasticSearchDemo::Utils::slurp_file($doc->{file}));
    $doc_data->{owner} = $doc->{owner};

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

  my $id = 1;
  foreach my $user (@{$self->{users}}) {
    carp "Indexing user $user->{fullname} document";
    $self->{es}->index(index   => $self->{index},
		       type    => $self->{auth}{type},
		       id      => $id++,
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

  return 
    (
     { # the administrator
      id       => 1,
      fullname => "Administrator",
      password => "admin",
      roles    => ["admin", "user"],
      username => "admin",
     },
     { # a first trackhub content provider
      id          => 2,
      first_name   => "Track",
      last_name   => "Hub1",
      affiliation => "EMBL-EBI",
      email       => "trackhub1\@ebi.ac.uk",
      fullname    => "TrackHub1",
      password    => "trackhub1",
      roles       => ["user"],
      username    => "trackhub1",
     },
     { # a second trackhub content provider
      id          => 3,
      first_name   => "Track",
      last_name   => "Hub2",
      affiliation => "UCSC",
      email       => "trackhub2\@ucsc.edu",
      fullname    => "TrackHub2",
      password    => "trackhub2",
      roles       => ["user"],
      username    => "trackhub2",
     },
     { # a third trackhub content provider
      id          => 4,
      first_name   => "Track",
      last_name   => "Hub3",
      affiliation => "Sanger",
      email       => "trackhub2\@sanger.ac.uk",
      fullname    => "TrackHub3",
      password    => "trackhub3",
      roles       => ["user"],
      username    => "trackhub3",
     },
    );
}

1;
