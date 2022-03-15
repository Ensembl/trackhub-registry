=head1 LICENSE

Copyright [2015-2022] EMBL-European Bioinformatics Institute

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

Registry::Controller::API::Registration - A controller for submitting track hubs to the Registry

=head1 DESCRIPTION

Implements endpoints allowing an authenticated user to submit track hubs to the Registry
and perform other operations with them, e.g. delete, retrieve information

=cut

package Registry::Controller::API::Registration;
use Moose;
use namespace::autoclean;

use JSON;
use Try::Tiny;
use File::Temp qw/ tempfile /;
use Registry::TrackHub::Translator;
use Registry::TrackHub::Validator;
use Params::Validate qw(SCALAR);

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
  default => 'application/json'
);

=head1 METHODS

=head2 begin

This is executed before any action managed by this controller. It checks whether the user
has authenticated and is submitting the request with an authorisation token.

=cut

sub begin : Private {
  my ($self, $c) = @_;

  # API-key based authentication
  # The client should have obtained an authorization token by a regular user+password
  # log in. Requests to this controller are made by attaching the username and
  # the auth token as headers
  #
  my $authorized = 0;
  if (exists($c->req->headers->{'user'}) && exists($c->req->headers->{'auth-token'})) {
    $authorized = $c->authenticate(
      { 
        username => $c->req->headers->{'user'}, 
        auth_key => $c->req->headers->{'auth-token'}
      },
      'authkey'
    );
  }

  $c->detach('status_unauthorized', 
     [ message => "You need to login, get an auth_token and make requests using the token" ] )
     unless $authorized;

  # We have overridden the Catalyst::Controller::REST default begin(), so we have to deserialize ourselves.
  $c->forward('deserialize');

  $c->stash(username => $c->req->headers->{'user'});
}

=head2 deserialize

Deserialise request.

=cut

sub deserialize : ActionClass('Deserialize') {}

=head2 trackdb_list

Return list of available documents for a given user, as document IDs 
mapped to the URI of the resource which represents the document

Action for /api/trackdb (GET), no arguments

=cut

sub trackdb_list :Path('/api/trackdb') Args(0) ActionClass('REST') { 
  my ($self, $c) = @_;  
}

=head2 trackdb_list_GET

Implements GET method of /api/trackdb

=cut

sub trackdb_list_GET { 
  my ($self, $c) = @_;

  # get all docs for the given user
  my $query = { term => { owner => lc $c->stash->{username} } };
  my $docs = $c->model('Search')->search_trackhubs(query => $query);

  my %trackhubs;
  foreach my $doc (@{$docs->{hits}{hits}}) {
    $trackhubs{$doc->{_id}} = 
      $c->uri_for('/api/trackdb/' . $doc->{_id})->as_string;
  }
  $self->status_ok($c, entity => \%trackhubs);
}

=head2 trackdb_create

Create new trackdb document

Action for /api/trackdb/create (POST)

=cut

sub trackdb_create :Path('/api/trackdb/create') Args(0) ActionClass('REST') {
  my ($self, $c) = @_;

  # get the version, if specified
  # otherwise set to default (from config parameter)
  my $version = $c->request->param('version') || Registry->config()->{TrackHub}{schema}{default};
  $c->log->debug('Handling submission with schema version: '.$version);
  if (! $self->_validate_schema_version($version) ) {
    $c->go('ReturnError', 'custom', ['Invalid version specified, pattern is /^v\d+\.\d+$/'])
  }
    
  $c->stash( version => $version ); 
}

=head2 trackdb_create_POST

Implements POST method for /api/trackdb/create

=cut

sub trackdb_create_POST {
  my ($self, $c) = @_;
  my $new_doc_data = $c->req->data;

  my $is_readonly = 0;
  $is_readonly = Registry->config()->{'read_only_mode'};

  if($is_readonly){
    return $self->status_bad_request($c, message => "Attention!! Server is running in READ-ONLY mode for essential maintenance.");
  }

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide a doc to create!")
    unless defined $new_doc_data;
  
    # set the owner of the doc as the current user
  $new_doc_data->{owner} = $c->stash->{username};
  $new_doc_data->{version} = $c->stash->{version};
  # set creation date/status 
  $new_doc_data->{created} = time();
  $new_doc_data->{status}{message} = 'Unchecked';

  my $id;
  try {
    # validate the doc
    # NOTE: the doc is not indexed if it does not validate (i.e. raises an exception)
    $self->_validate($c, to_json($new_doc_data));

    # prevent submission of duplicate content, i.e. trackdb
    # with the same hub/assembly
    my $hub = $new_doc_data->{hub}{name};
    my $assembly_acc = $new_doc_data->{assembly}{accession};
    unless (defined $hub and defined $assembly_acc) {
      $c->go('ReturnError', 'custom', ["Unable to find hub/assembly information without defined assembly accession and hub name"]);
    }

    my $count = $c->model('Search')->count_existing_hubs($c->stash->{username}, $hub, $assembly_acc);

    if ($count != 0) {
      $c->go('ReturnError', 'custom', ["Cannot submit: a document with the same hub/assembly already exists"]);
    }
	
    my $config = Registry->config()->{'Model::Search'};
    $id = $c->model('Search')->index(
      index   => $config->{trackhub}{index},
      type    => $config->{trackhub}{type},
      body    => $new_doc_data
    )->{_id};

    # refresh the index
    $c->model('Search')->indices->refresh(index => $config->{trackhub}{index});
  } catch {
    $c->go('ReturnError', 'custom', [q{$_}]);
  };

  $self->status_created( $c,
    location => $c->uri_for( '/api/trackdb/' . $id )->as_string,
    entity   => $c->model('Search')->get_trackhub_by_id($id)
  );
}


=head2 trackhub

Return the track data hubs for the requesting user.
Actions for /api/trackhub (GET|POST)

=cut 

sub trackhub :Path('/api/trackhub') Args(0) ActionClass('REST') {
  my ($self, $c) = @_;

  # get the version, if specified
  # otherwise set to default (from config parameter)
  my $version = $c->request->param('version') || Registry->config()->{TrackHub}{schema}{default};
  $c->log->debug('Handling submission with schema version: '.$version);

  if (! $self->_validate_schema_version($version)) {
    $c->go('ReturnError', 'custom', ['Invalid version specified, pattern is /^v\d+\.\d+$/']);
  }
  
  # read param which prevent hubCheck running,
  # this is hidden to the user 
  my $permissive = $c->request->param('permissive');
  
  $c->stash( version => $version, permissive => $permissive ); 
}

=head2 trackhub_GET

Return the list of available track data hubs for a given user.
Each trackhub is listed with key/value parameters together with
a list of URIs of the resources which corresponds to the trackDbs
beloning to the track hub

=cut

sub trackhub_GET {
  my ($self, $c) = @_;

  # get all docs for the given user
  my $trackdbs = $c->model('Search')->get_trackdbs(query => { term => { owner => $c->stash->{username} } });

  my $results;
  foreach my $trackdb (@{$trackdbs}) {
    my $hub = $trackdb->{_source}{hub}{name};
    $results->{$hub} = $trackdb->{_source}{hub} unless exists $results->{$hub};

    push @{$results->{$hub}{trackdbs}},
      {
       species  => $trackdb->{_source}{species}{tax_id},
       assembly => $trackdb->{_source}{assembly}{accession},
       uri      => $c->uri_for('/api/trackdb/' . $trackdb->{_source}{_id})->as_string
      };
  }

  my @trackhubs = values %{$results};
  $self->status_ok($c, entity => \@trackhubs);
}

# Create/update trackdb documents from a remote public TrackHub (UCSC spec)

=head2 trackhub_POST

Implement POST method for /api/trackhub. This is the action with which a track hub
is submitted to the Registry.

=cut

sub trackhub_POST {
  my ($self, $c) = @_;

  # if the client didn't supply any data, it didn't send a properly formed request

  if (! defined $c->req->data) {
    return $self->status_bad_request($c, message => "You must provide data with the POST request")
  }

  # read parameters, remote hub URL/type/assembly maps
  my $url = $c->req->data->{url};
  my $trackdb_type = 'genomics';
  if (exists $c->req->data->{type}) {
    $trackdb_type = lc $c->req->data->{type}
  }

  my $assembly_map = $c->req->data->{assemblies}; # might have submitted name -> accession map in case of non-UCSC assemblies
  # whether the trackDbs are available for search or not, default: yes
  my $public = JSON::true;
  if ( defined $c->req->data->{public} ) {
    if ( $c->req->data->{public} ) { # rely on Perl truthiness to catch everything but 0
      $public = JSON::true;
    } else {
      $public = JSON::false;
    }
  }
  
  if (! defined $url) {
    return $self->status_bad_request($c, message => 'You must specify the remote trackhub URL');
  }
  # Add hub.txt to hub URL in case it is missing
  # The hub might be submitted with or without the hub.txt in the URL so we
  # standardise on it being in the URL, and add hub.txt when it is absent
  if ($url !~ /\.txt$/) {
    $url .= '/' unless $url =~ /\/$/;
    $url .= 'hub.txt';
  }

  $c->log->info("Request to create/update TrackHub at $url");
  #
  # prevent submission of a hub submitted by another user
  #

  my $previous_instances = $c->model('Search')->get_hub_by_url($url);

  if (scalar(@$previous_instances) > 0 && $previous_instances->[0]{_source}{owner} ne $c->stash->{username}) {
    $c->go('ReturnError', 'custom', ['Cannot submit a track hub registered by another user']);
  }

  # Use the created timestamp from the previously submitted version of the hub
  my $created;
  if (scalar @$previous_instances) {
    $created = $previous_instances->[0]->{_source}{created};
  }
  my @docs_to_insert;
  
  # Validate the submitted hub

  my ($location, $entity); # Return values for submitter
  try {
    $c->log->info("Translating TrackHub at $url");
    my $translator = Registry::TrackHub::Translator->new(
      version => $c->stash->{version}, 
      permissive => $c->stash->{permissive}, 
      assemblies => $assembly_map
    );

    # assembly can be left undefined by the user
    # in this case, we get a list of translations of all different 
    # assembly trackdb files in the hub
    my $trackdbs_docs = $translator->translate($url);

    foreach my $json_doc (@{$trackdbs_docs}) {
      my $doc = from_json($json_doc);
      
      $doc->{public} = $public; # i.e. if public = 1, all submitted hubs become public

      $doc->{type} = $trackdb_type;

      # validate the document. Do not index if validation fails.
      $self->_validate($c, $json_doc);

      $doc->{owner} = $c->stash->{username};
      # set creation/update date/status 
      if ($created) {
        $doc->{created} = $created;
        $doc->{updated} = time();
      }
      else {
        $doc->{created} = time();
      }

      push @docs_to_insert,$doc;
    }
  } catch {
    # Validation error has occurred.
    # Do not delete prior track, and complain to submitter

    $c->go('ReturnError', 'custom', [$_->message]);

  };

  # Now all submitted items are validated, delete anything with the same URL

  if (scalar @{$previous_instances}) {
    # This is not in compliance with HTTP standards. Replacing a document should be done with PUT or PATCH
    # The correct response here is to say: "You've already created that document"
    $c->log->info("TrackHub already registered: $url. Deleting existing trackDBs");
    foreach my $doc (@{$previous_instances}) {
      $c->model('Search')->delete_hub_by_id($doc->{_id});
      $c->log->info(sprintf "Deleted trackDb [%s]", $doc->{_id});
    }
  }
  
  # Insert the new documents

  foreach my $new_doc (@docs_to_insert) {
    my $id = $c->model('Search')->create_trackdb($new_doc);
    $c->log->info(sprintf "Created trackDb [%s] (%s)", $id, $new_doc->{assembly}{name});
  
    $c->model('Search')->refresh_trackhub_index;

    push @{$location}, $c->uri_for( '/api/trackdb/' . $id )->as_string;
    push @{$entity}, $c->model('Search')->get_trackhub_by_id($id);
  }

  # location in status_created can be either a scalar or a blessed reference
  bless($location, 'Location');
  $self->status_created( 
    $c,
    location => $location,
    entity   => $entity
  );
}

=head2 trackhub_by_name

Actions for /api/trackhub/:id (GET, DELETE)

=cut 

sub trackhub_by_name :Path('/api/trackhub') Args(1) ActionClass('REST') { 
  my ($self, $c, $hubid) = @_;

  my $query = {
    bool => {
      must => [
        { term => { owner => $c->stash->{username} } },
        { term => { 'hub.name' => $hubid } }
      ]
    }
  };

  my $trackdbs;
  try {
    $trackdbs = $c->model('Search')->get_trackdbs(query => $query);
  } catch {
    $c->go('ReturnError', 'custom', [$_->message]);
  };

  $c->stash(trackdbs => $trackdbs);
  
}

=head2 trackhub_by_name_GET

Returns the set of trackDB documents associated to the given track hub.

=cut

sub trackhub_by_name_GET {
  my ($self, $c, $hubid) = @_;
  my $trackdbs = $c->stash->{trackdbs};

  # this doesn't work if we put the following in the parent method
  return $self->status_not_found($c, message => "Could not find trackDBs attached to hub $hubid")
    unless scalar @{$trackdbs};

  my $trackhub;
  foreach my $trackdb (@{$trackdbs}) {
    # record trackhub attributes
    map { $trackhub->{$_} = $trackdb->{_source}{hub}{$_} } qw / name shortLabel longLabel url /
      unless defined $trackhub;

    push @{$trackhub->{trackdbs}},
      {
        species  => $trackdb->{_source}{species},
        assembly => $trackdb->{_source}{assembly},
        uri      => $c->uri_for('/api/trackdb/' . $trackdb->{_source}{_id})->as_string
      };
  }

  $self->status_ok($c, entity => $trackhub);
}

=head2 trackhub_by_name_DELETE

Delete the set of trackDB docs associated to the given track hub.

=cut

sub trackhub_by_name_DELETE {
  my ($self, $c, $hubid) = @_;
  my $trackdbs = $c->stash->{trackdbs};

  # this doesn't work if we put the following in the parent method
  if (! scalar @{$trackdbs}) {
    return $self->status_not_found($c, message => "Could not find trackDBs attached to hub $hubid");
  }

  my $config = Registry->config()->{'Model::Search'};
  my ($index, $type) = ($config->{trackhub}{index}, $config->{trackhub}{type});

  #
  # TODO: could forward to DELETE /api/trackdb instead
  #
  try {
    foreach my $trackdb (@{$trackdbs}) {
      $c->model('Search')->delete(
        index   => $index,
        type    => $type,
        id      => $trackdb->{_id}
      );
    }
  } catch {
    $c->go('ReturnError', 'custom', [$_->message]);
  };

  $c->model('Search')->indices->refresh(index => $index);
  $self->status_ok($c, entity => { message => "Deleted trackDBs from track hub $hubid" });
}

=head2 _validate

Validate trackDB JSON document according to a given schema.

=cut

sub _validate: Private {
  my ($self, $c, $doc) = @_;
  
  my $version = $c->stash->{version};
  
  my $validator = 
    Registry::TrackHub::Validator->new(schema => Registry->config()->{TrackHub}{schema}{$version});
  # Put the submitted JSON into a file, so it can be validated by a Python tool
  my ($fh, $filename) = tempfile( DIR => Registry->config()->{TrackHub}{schema}{validate}, SUFFIX => '.json', UNLINK => 1 );
  print $fh $doc;
  close $fh;

  # exceptions might be raised when:
  # - cannot run validation script 
  # - JSON is not valid under specified schema
  # 
  # WARNING
  # It's necessary to put the validation exception handling
  # code here, even if the call to this method is already
  # enclosed in a try/catch block, because it's usually
  # called with forward which automatically eval (i.e. handle
  # any exception) the call
  try {
    $validator->validate($filename);
  } catch {
    unlink $filename or $c->log->warn("Couldn't remove file $filename");
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };
  
  unlink $filename or $c->log->warn("Couldn't remove file $filename");
  return;
}

=head2 _validate_schema_version

Checks a supplied trackhub version for validity

=cut

sub _validate_schema_version {
  my ($self,$version) = @_;
  return $version =~ /^v\d+\.\d+$/;
}


=head2 trackdb 

Actions for /api/trackdb/:id (GET|PUT|DELETE)

=cut

sub trackdb :Path('/api/trackdb') Args(1) ActionClass('REST') {
  my ($self, $c, $doc_id) = @_;

  # if the doc with that ID doesn't exist, ES throws exception
  # intercept but do nothing, as the GET method will handle
  # the situation in a REST appropriate way.
  eval { $c->stash(trackhub => $c->model('Search')->get_trackhub_by_id($doc_id)); };
}

=head2 trackdb_GET

Return trackhub document content for a document with the specified ID

=cut

sub trackdb_GET {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{trackhub};
  if ($trackhub) {
    if ($trackhub->{owner} eq $c->stash->{username}) {
      $self->status_ok($c, entity => $trackhub) if $trackhub;
    } else {
      $self->status_bad_request($c, message => sprintf "Cannot fetch: document (ID: %d) does not belong to user %s", $doc_id, $c->stash->{username});
    }
  } else {
    $self->status_not_found($c, message => "Could not find trackhub doc (ID: $doc_id)");    
  }
}

=head2 trackdb_PUT

Update document content for a document with the specified ID

=cut

sub trackdb_PUT {
  my ($self, $c, $doc_id) = @_;
  
  # cannot update the doc if:
  # - the doc with that ID doesn't exist
  # - it doesn't belong to the user
  return $self->status_not_found($c, message => "Cannot update: document (ID: $doc_id) does not exist")
    unless $c->stash->{trackhub};

  return $self->status_bad_request($c, message => sprintf "Cannot update: document (ID: %d) does not belong to user %s", $doc_id, $c->stash->{username})
    unless $c->stash->{trackhub}{owner} eq $c->stash->{username};

  # need the version from the original doc
  # in order to validate the updated version
  my $version = $c->stash->{trackhub}{version};
  $c->go('ReturnError', 'custom', ["Couldn't get version from original trackdb document"])
    unless $version;
  if (! $self->_validate_schema_version($version)) {
    $c->go('ReturnError', 'custom', ["Invalid version from original trackdb document"])
  }
  $c->stash(version => $version);

  my $new_doc_data = $c->req->data;

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "No body in your trackhub update request")
    unless defined $new_doc_data;

  # set the owner as the current user
  # and reset the created date/time
  $new_doc_data->{owner} = $c->stash->{username};
  $new_doc_data->{created} = $c->stash->{trackhub}{created};

  # validate the updated version
  try {
    # validate the updated doc
    # NOTE: the doc is not indexed if it does not validate (i.e. raises an exception)
    $self->_validate($c, to_json($new_doc_data));
    
    # prevent submission of duplicate content, i.e. trackdb
    # with the same hub/assembly
    my $hub = $new_doc_data->{hub}{name};
    my $assembly_acc = $new_doc_data->{assembly}{accession};
    unless( defined $hub and defined $assembly_acc) {
      $c->go('ReturnError', 'custom', ['Unable to find hub/assembly information']);
    }
    
    my $duplicate_docs = $c->model('Search')->get_existing_hubs($c->stash->{username},$hub,$assembly_acc);
    if (@$duplicate_docs) {
      foreach my $doc (@$duplicate_docs) {
        $c->go('ReturnError', 'custom', ['Cannot submit: a document when the same hub/assembly exists'])
        if $doc->{_id} != $doc_id;
      }
    }
    
    # set update time and reset status
    $new_doc_data->{updated} = time();
    $new_doc_data->{status}{message} = 'Unchecked';

    #
    # Updates in Elasticsearch
    # http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/partial-updates.html
    #
    # Partial updates can be done through the update API, which accepts a partial document.
    # However, this just gets merged with the existing document, so the only way to actually
    # update a document is to retrieve it, change it, then reindex the whole document.
    #
    my $config = Registry->config()->{'Model::Search'};
    $c->model('Search')->index(
      index   => $config->{trackhub}{index},
      type    => $config->{trackhub}{type},
      id      => $doc_id,
      body    => $new_doc_data
    );

    # refresh the index
    $c->model('Search')->indices->refresh(index => $config->{trackhub}{index});
  } catch {
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };

  $self->status_ok( $c, entity => $c->model('Search')->get_trackhub_by_id($doc_id));
  
}

=head2 trackdb_DELETE

Delete a document with the specified ID

=cut

sub trackdb_DELETE {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{'trackhub'};
  if ($trackhub) {
    if ($trackhub->{owner} ne $c->stash->{username}) {
      return $self->status_bad_request(
        $c,
        message => sprintf "Cannot delete: document (ID: %d) does not belong to user %s", $doc_id, $c->stash->{username}
      );
    }

    #
    # http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/delete-doc.html
    #
    # As already mentioned in Updating a whole document, deleting a document doesn’t immediately 
    # remove the document from disk — it just marks it as deleted. Elasticsearch will clean up 
    # deleted documents in the background as you continue to index more data.
    #
    # https://metacpan.org/pod/Search::Elasticsearch::Client::Direct#delete
    #
    # The delete() method will delete the document with the specified 
    # index, type and id, or will throw a Missing error.
    #
    my $config = Registry->config()->{'Model::Search'};
    try {
      $c->model('Search')->delete(
        index   => $config->{trackhub}{index},
        type    => $config->{trackhub}{type},
        id      => $doc_id);
      $c->model('Search')->indices->refresh(index => $config->{trackhub}{index});
    } catch {
      $c->go('ReturnError', 'custom', [qq{$_}]);
    };

    $self->status_ok($c, entity => $trackhub) if $trackhub;
  } else {
    $self->status_not_found($c, message => "Could not find trackhub $doc_id");    
  }
}

=head2 status_unauthorized

Returns a "401 Unauthorized" response.  Takes a "message" argument
as a scalar, which will become the value of "error" in the serialized
response.

Example:

  $self->status_unauthorized(
    $c,
    message => "Cannot do what you have asked!",
  );

=cut

sub status_unauthorized : Private {
  my $self = shift;
  my $c    = shift;
  my %p    = Params::Validate::validate( @_, { message => { type => SCALAR }, }, );

  $c->response->status(401);
  $c->log->debug( "Status Unauthorized: " . $p{message} ) if $c->debug;
  $self->_set_entity( $c, { error => $p{message} } );
  return 1;
}


=head2 error

=cut

sub error : Path('/api/error') Args(0) ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $c->log->error($error_msg);
    
  $self->status_bad_request( $c, message => $error_msg );
}

=head2 error_GET

=cut

sub error_GET { }

=head2 error_POST

=cut

sub error_POST { }

=head2 error_PUT

=cut

sub error_PUT { }

=head2 error_DELETE

=cut

sub error_DELETE { }

=head2 error_HEAD

=cut

sub error_HEAD { }

=head2 error_OPTIONS

=cut

sub error_OPTIONS { }


=head2 logout

=cut 

sub logout :Path('/api/logout') Args(0) ActionClass('REST') { }

=head2 logout_GET

=cut

sub logout_GET {
  my ($self, $c) = @_;
  $c->user->auth_key(undef); # Remove the API key from the record
  $c->user->update;

  $self->status_ok($c, entity => { message => 'Successfully logged out' });
}

__PACKAGE__->meta->make_immutable;

1;
