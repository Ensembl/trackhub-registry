package Registry::Controller::API;
use Moose;
use namespace::autoclean;

use JSON;
use List::Util 'max';
use String::Random;
use Try::Tiny;
use File::Temp qw/ tempfile /;
use Registry::TrackHub::Translator;
use Registry::TrackHub::Validator;

BEGIN { extends 'Catalyst::Controller::REST'; }
use Params::Validate qw(SCALAR);

__PACKAGE__->config(
		    'default'   => 'application/json',
		    # map => {
		    # 	    'text/plain' => ['YAML'],
		    # 	   }
		   );

=head1 NAME

Registry::Controller::API - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 begin

=cut

sub begin : Private {
  my ($self, $c) = @_;

  # ... do things before Deserializing ... 
  # 
  # API-key based authentication
  # The client should have obtained an authorization token
  # and submit the request by attaching the username and
  # the auth token as headers
  #
  my $authorized = 0;
  if (exists($c->req->headers->{'user'}) && exists($c->req->headers->{'auth-token'})) {
    $authorized = $c->authenticate({ username => $c->req->headers->{'user'}, 
				     auth_key => $c->req->headers->{'auth-token'} }, 'testauthkey');
  }

  $c->forward('deserialize');

  # ... do things after Deserializing ...
  #
  # Deny access in case API-key authorization fails,
  # otherwise allow normal dispatch chain
  #
  $c->detach('status_unauthorized', 
	     [ message => "You need to login, get an auth_token and make requests using the token" ] )
    unless $authorized;

  $c->stash(user => $c->req->headers->{'user'});

  # $c->detach('/api/error', [ 'You need to login, get an auth_token and make requests using the token' ])
  #   unless $authorized;
}

sub deserialize : ActionClass('Deserialize') {}

=head2 auto

Works with normal HTTP basic auth, but errors occur
when trying to use it to support API key authentication
for all endpoints.

I suspect it depends on the way the REST controller 
overrides the dispatch chain.

The intended functionality is implemented by overriding
the begin method.

=cut 

# sub auto : Private {
#   my ($self, $c) = @_;
#   $c->authenticate();
# }

=head2 list_endpoints

List available endpoints

=cut

sub list_endpoints :Path('/api') Args(0) {
  my ($self, $c) = @_;

  my @endpoints = 
    (
     ['/api/trackhub', 'GET', 'Return the list of available docs (id => URI)'],
     ['/api/trackhub/create', 'PUT', 'Create new trackhub document'],
     ['/api/trackhub/create', 'POST', 'Create new trackhub document by converting assembly trackdbs from a remote public hub'],
     ['/api/trackhub/:id', 'GET', 'Return content for a document with the specified ID'],
     ['/api/trackhub/:id', 'POST', 'Update content for a document with the specified ID'],
     ['/api/trackhub/:id', 'DELETE', 'Delete document with the specified ID']
    );
  $c->stash( template  => 'endpoints.tt',
	     endpoints => \@endpoints);
  $c->forward( $c->view('HTML') );
}

=head2 trackhub_list

Return list of available documents for a given user, as document IDs 
mapped to the URI of the resource which represents the document

Action for /api/trackhub (GET), no arguments

=cut

sub trackhub_list :Path('/api/trackhub') Args(0) ActionClass('REST') { 
  my ($self, $c) = @_;  
}

sub trackhub_list_GET { 
  my ($self, $c) = @_;

  # get all docs for the given user
  my $query = { term => { owner => $c->stash->{user} } };
  # TODO: use scan and scroll to retrieve large number of results efficiently
  # See: https://www.elastic.co/guide/en/elasticsearch/guide/current/scan-scroll.html#scan-scroll
  my $docs = $c->model('Search')->search_trackhubs(query => $query);

  my %trackhubs;
  foreach my $doc (@{$docs->{hits}{hits}}) {
    $trackhubs{$doc->{_id}} = 
      $c->uri_for('/api/trackhub/' . $doc->{_id})->as_string;
  }
  $self->status_ok($c, entity => \%trackhubs);

  # $self->status_no_content($c);
}

=head2 trackhub_create

Create new trackhub document

Action for /api/trackhub/create (PUT,POST)

=cut

sub trackhub_create :Path('/api/trackhub/create') Args(0) ActionClass('REST') {
  my ($self, $c) = @_;

  # get the version, if specified
  # otherwise set to default (from config parameter)
  my $version = $c->request->param('version') || Registry->config()->{TrackHub}{schema}{default};
  $c->go('ReturnError', 'custom', ["Invalid version specified, pattern is /^v\\d+\.\\d\$"])
    unless $version =~ /^v\d+\.\d$/;
  
  # read param which prevent hubCheck running,
  # this is hidden to the user 
  my $permissive = $c->request->param('permissive');
  
  # get the count of trackhubs to determine the ID of the doc to create
  my $current_max_id = $c->model('Search')->count_trackhubs()->{count};
  $c->stash( id =>  $current_max_id?++$current_max_id:1, version => $version, permissive => $permissive ); 
}

sub trackhub_create_PUT {
  my ($self, $c) = @_;
  my $new_doc_data = $c->req->data;

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide a doc to create!")
    unless defined $new_doc_data;
  
  my $id = $c->stash()->{id};
  if ($id) {
    # set the owner of the doc as the current user
    $new_doc_data->{owner} = $c->stash->{user};
    $new_doc_data->{version} = $c->stash->{version};
    # set creation date/status 
    $new_doc_data->{created} = time();
    $new_doc_data->{status}{message} = 'Unknown';

    try {
      # validate the doc
      # NOTE: the doc is not indexed if it does not validate (i.e. raises an exception)
      $c->forward('_validate', [ to_json($new_doc_data) ]);

      # prevent submission of duplicate content, i.e. trackdb
      # with the same hub/assembly
      my $hub = $new_doc_data->{hub}{name};
      my $assembly_acc = $new_doc_data->{assembly}{accession};
      defined $hub and defined $assembly_acc or
	$c->go('ReturnError', 'custom', ["Unable to find hub/assembly information"]);
      my $query = {
		   filtered => {
				filter => {
					   bool => {
						    must => [
							     { term => { owner => $c->stash->{user} } },
							     { term => { 'hub.name' => $hub } },
							     { term => { 'assembly.accession' => $assembly_acc } }
							    ]
						   }
					  }
			       }
		  };
      $c->go('ReturnError', 'custom', ["Cannot submit: a document with the same hub/assembly exists"])
	if $c->model('Search')->count_trackhubs(query => $query)->{count};
	
      my $config = Registry->config()->{'Model::Search'};
      $c->model('Search')->index(index   => $config->{index},
				 type    => $config->{type}{trackhub},
				 id      => $id,
				 body    => $new_doc_data);

      # refresh the index
      $c->model('Search')->indices->refresh(index => $config->{index});
    } catch {
      $c->go('ReturnError', 'custom', [qq{$_}]);
    };
  } else {
    $c->go('ReturnError', 'custom', ["Couldn't determine doc ID(s)"]);
  }

  $self->status_created( $c,
			 location => $c->uri_for( '/api/trackhub/' . $id )->as_string,
			 entity   => $c->model('Search')->get_trackhub_by_id($id));
}

sub trackhub_create_POST {
  my ($self, $c) = @_;
  # if the client didn't supply any data, it didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide data with the POST request")
    unless defined $c->req->data;

  # read parameters, remote hub URL/type
  my $url = $c->req->data->{url};
  my $trackdb_type = $c->req->data->{type} || 'genomics'; # default to genomics type

  return $self->status_bad_request($c, message => "You must specify the remote trackhub URL")
    unless defined $url;

  my ($id, $version, $permissive) = ($c->stash->{id}, $c->stash->{version}, $c->stash->{permissive});
  my $config = Registry->config()->{'Model::Search'};
  my ($location, $entity);

  my @indexed;
  if ($id) {
    try {
      my $translator = Registry::TrackHub::Translator->new(version => $version, permissive => $permissive);

      # assembly can be left undefined by the user
      # in this case, we get a list of translations of all different 
      # assembly trackdb files in the hub
      my $trackdbs_docs = $translator->translate($url);

      foreach my $json_doc (@{$trackdbs_docs}) {
	my $doc = from_json($json_doc);
      
	# add type
	$doc->{type} = $trackdb_type;

	# validate the doc
	# NOTE: the doc is not indexed if it does not validate (i.e. raises an exception)
	$c->forward('_validate', [ $json_doc ]);

	# prevent submission of duplicate content, i.e. trackdb
	# with the same hub/assembly
	my $hub = $doc->{hub}{name};
	my $assembly_acc = $doc->{assembly}{accession};
	defined $hub and defined $assembly_acc or
	  $c->go('ReturnError', 'custom', ["Unable to find hub/assembly information"]);
	my $query = {
		     filtered => {
				  filter => {
					     bool => {
						      must => [
							       { term => { owner => $c->stash->{user} } },
							       { term => { 'hub.name' => $hub } },
							       { term => { 'assembly.accession' => $assembly_acc } }
							      ]
						     }
					    }
				 }
		    };
	$c->go('ReturnError', 'custom', ["Cannot submit: a document with the same hub/assembly exists"])
	  if $c->model('Search')->count_trackhubs(query => $query)->{count};

	# set the owner of the doc as the current user
	$doc->{owner} = $c->stash->{user};
	# set creation date/status 
	$doc->{created} = time();
	$doc->{status}{message} = 'Unknown';
	
	$c->model('Search')->index(index   => $config->{index},
				   type    => $config->{type}{trackhub},
				   id      => $id,
				   body    => $doc);
	# refresh the index
	$c->model('Search')->indices->refresh(index => $config->{index});
	# record id of indexed doc so we can roll back in case of any failure
	push @indexed, $id;

	$location .= $c->uri_for( '/api/trackhub/' . $id )->as_string . ',';
	$entity->{$id} = $c->model('Search')->get_trackhub_by_id($id);

	$id++;
      };
    } catch {
      # TODO: roll back and delete any doc which has been indexed previous to the error
      # NOTE: not sure this is the correct way, since /api/trackhub/:id (GET|POST|DELETE)
      #       all expect the trackhub doc to be loaded in the stash
      # map { $c->forward("trackhub_DELETE", $id) } @indexed;

      $c->go('ReturnError', 'custom', [qq{$_}]);
    };
  } else {
    $c->go('ReturnError', 'custom', ["Couldn't determine doc ID(s)"]);
  }

  $location =~ s/,$//;
  $self->status_created( $c,
			 location => $location,
			 entity   => $entity);
}

sub _validate: Private {
  my ($self, $c, $doc) = @_;
  
  my $version = $c->stash->{version};
  
  my $validator = 
    Registry::TrackHub::Validator->new(schema => Registry->config()->{TrackHub}{schema}{$version});
  my ($fh, $filename) = tempfile( DIR => '.', SUFFIX => '.json', UNLINK => 1);
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
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };
    
  return;
}

=head2 trackhub 

Actions for /api/trackhub/:id (GET|POST|DELETE)

=cut

sub trackhub :Path('/api/trackhub') Args(1) ActionClass('REST') {
  my ($self, $c, $doc_id) = @_;

  # if the doc with that ID doesn't exist, ES throws exception
  # intercept but do nothing, as the GET method will handle
  # the situation in a REST appropriate way.
  eval { $c->stash(trackhub => $c->model('Search')->get_trackhub_by_id($doc_id)); };
}

=head2 trackhub_GET

Return trackhub document content for a document
with the specified ID

=cut

sub trackhub_GET {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{trackhub};
  if ($trackhub) {
    if ($trackhub->{owner} eq $c->stash->{user}) {
      $self->status_ok($c, entity => $trackhub) if $trackhub;
    } else {
      $self->status_bad_request($c, message => sprintf "Cannot fetch: document (ID: %d) does not belong to user %s", $doc_id, $c->stash->{user});
    }
  } else {
    $self->status_not_found($c, message => "Could not find trackhub doc (ID: $doc_id)");    
  }
}

=head2 trackhub_POST

Update document content for a document
with the specified ID

=cut

sub trackhub_POST {
  my ($self, $c, $doc_id) = @_;
  
  # cannot update the doc if:
  # - the doc with that ID doesn't exist
  # - it doesn't belong to the user
  return $self->status_bad_request($c, message => "Cannot update: document (ID: $doc_id) does not exist")
    unless $c->stash()->{trackhub};

  return $self->status_bad_request($c, message => sprintf "Cannot update: document (ID: %d) does not belong to user %s", $doc_id, $c->stash->{user})
    unless $c->stash->{trackhub}{owner} eq $c->stash->{user};

  # need the version from the original doc
  # in order to validate the updated version
  my $version = $c->stash->{trackhub}{version};
  $c->go('ReturnError', 'custom', ["Couldn't get version from original trackdb document"])
    unless $version;
  $c->go('ReturnError', 'custom', ["Invalid version from original trackdb document"])
    unless $version =~ /^v\d+\.\d$/;
  $c->stash(version => $version);

  my $new_doc_data = $c->req->data;

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide a doc to modify!")
    unless defined $new_doc_data;

  # set the owner as the current user
  # and reset the created date/time
  $new_doc_data->{owner} = $c->stash->{user};
  $new_doc_data->{created} = $c->stash->{trackhub}{created};

  # validate the updated version
  try {
    # validate the updated doc
    # NOTE: the doc is not indexed if it does not validate (i.e. raises an exception)
    $c->forward('_validate', [ to_json($new_doc_data) ]);
    
    # prevent submission of duplicate content, i.e. trackdb
    # with the same hub/assembly
    my $hub = $new_doc_data->{hub}{name};
    my $assembly_acc = $new_doc_data->{assembly}{accession};
    defined $hub and defined $assembly_acc or
      $c->go('ReturnError', 'custom', ["Unable to find hub/assembly information"]);
    my $query = {
		 filtered => {
			      filter => {
					 bool => {
						  must => [
							   { term => { owner => $c->stash->{user} } },
							   { term => { 'hub.name' => $hub } },
							   { term => { 'assembly.accession' => $assembly_acc } }
							  ]
						 }
					}
			     }
		};
    # TODO: use scan and scroll to retrieve large number of results efficiently
    my $duplicate_docs = $c->model('Search')->search_trackhubs(size => 100000, query => $query)->{hits};
    if ($duplicate_docs->{total}) {
      foreach my $doc (@{$duplicate_docs->{hits}}) {
	$c->go('ReturnError', 'custom', ["Cannot submit: a document with the same hub/assembly exists"])
	  if $doc->{_id} != $doc_id;
      }
    }
    
    # set update time and reset status
    $new_doc_data->{updated} = time();
    $new_doc_data->{status}{message} = 'Unknown';

    #
    # Updates in Elasticsearch
    # http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/partial-updates.html
    #
    # Partial updates can be done through the update API, which accepts a partial document.
    # However, this just gets merged with the existing document, so the only way to actually
    # update a document is to retrieve it, change it, then reindex the whole document.
    #
    my $config = Registry->config()->{'Model::Search'};
    $c->model('Search')->index(index   => $config->{index},
			       type    => $config->{type}{trackhub},
			       id      => $doc_id,
			       body    => $new_doc_data);

    # refresh the index
    $c->model('Search')->indices->refresh(index => $config->{index});
  } catch {
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };

  $self->status_ok( $c, entity => $c->model('Search')->get_trackhub_by_id($doc_id));
  
}

=head2 trackhub_DELETE

Delete a document with the specified ID

=cut

sub trackhub_DELETE {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{'trackhub'};
  if ($trackhub) {
    return $self->status_bad_request($c, message => sprintf "Cannot delete: document (ID: %d) does not belong to user %s", $doc_id, $c->stash->{user})
    unless $trackhub->{owner} eq $c->stash->{user};

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
    $c->model('Search')->delete(index   => $config->{index},
				type    => $config->{type}{trackhub},
				id      => $doc_id);

    $self->status_ok($c, entity => $trackhub) if $trackhub;
  } else {
    $self->status_not_found($c, message => "Could not find trackhub $doc_id");    
  }
}

=item status_unauthorized

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
  $c->log->debug( "Status Unauthorized: " . $p{'message'} ) if $c->debug;
  $self->_set_entity( $c, { error => $p{'message'} } );
  return 1;
}


=head2 error



=cut

sub error : Path('/api/error') Args(0) ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $c->log->error($error_msg);
    
  $self->status_bad_request( $c, message => $error_msg );
}

sub error_GET { }
sub error_POST { }
sub error_PUT { }
sub error_DELETE { }
sub error_HEAD { }
sub error_OPTIONS { }


__PACKAGE__->meta->make_immutable;

1;

# BEGIN { extends 'Catalyst::Controller' }

#
# Matching Actions on Request Content Types,
# a feature introduced since v5.90050
#
# See http://www.catalystframework.org/calendar/2013/8
# 
# __PACKAGE__->config(
#   action => {
#     '*' => {
#       # Attributes common to all actions
#       # in this controller
#       Consumes => 'JSON',
#       Path => '',
#     }
#   }
# );

# =head2 index
 
# =cut

# sub index :Path :Args(0) {
#   my ( $self, $c ) = @_;

#   #
#   # TODO: should handle POST data
#   #
#   my $username = $c->request->params->{username} || "";
#   my $password = $c->request->params->{password} || "";
#   if ($username && $password) {
#     # Attempt to authenticate the user
#     if ($c->authenticate({ username => $username,
#                            password => $password} )) {
#       # return welcome message
#       $c->stash->{data} = { msg => "Welcome user $username" };
#       return;
#     } else {
#       # Set an error message
#       $c->detach('error', [ 401, 'Unauthorized' ]);
#     }
#   } 

#   $c->detach('error', [401, 'Please specify username/password credentials']);
# }

# # end action is always called at the end of the route
# sub end :Private {
#   my ( $self, $c ) = @_;

#   # Render the stash using our JSON view
#   $c->forward($c->view('JSON'));
# }
 
# We use the error action to handle errors
# sub error :Private {
#   my ( $self, $c, $code, $reason ) = @_;
#   $reason ||= 'Unknown Error';
#   $code ||= 500;
 
#   $c->res->status($code);
#   # Error text is rendered as JSON as well
#   $c->stash->{data} = { error => $reason };
# }

=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

