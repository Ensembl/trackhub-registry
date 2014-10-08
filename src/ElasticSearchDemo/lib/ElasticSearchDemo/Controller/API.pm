package ElasticSearchDemo::Controller::API;
use Moose;
use namespace::autoclean;

use List::Util 'max';
use String::Random;

BEGIN { extends 'Catalyst::Controller::REST'; }
use Params::Validate qw(SCALAR);

__PACKAGE__->config(
		    'default'   => 'application/json',
		    # map => {
		    # 	    'text/plain' => ['YAML'],
		    # 	   }
		   );

=head1 NAME

ElasticSearchDemo::Controller::API - Catalyst Controller

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
     ['/api/trackhub/:id', 'GET', 'Return content for a document with the specified ID'],
     ['/api/trackhub/:id', 'POST', 'Update content for a document with the specified ID'],
     ['/api/trackhub/:id', 'DELETE', 'Delete document with the specified ID']
    );
  $c->stash( template  => 'endpoints.tt',
	     endpoints => \@endpoints);
  $c->forward( $c->view('HTML') );
}

=head2 trackhub_list

Return list of available documents, as document IDs 
mapped to the URI of the resource which represents 
the document

Action for /api/trackhub (GET), no arguments

=cut

sub trackhub_list :Path('/api/trackhub') Args(0) ActionClass('REST') { 
  my ($self, $c) = @_;  
}

sub trackhub_list_GET { 
  my ($self, $c) = @_;

  # no query arg default to get all docs
  my $docs = $c->model('ElasticSearch')->query(index => 'test', type => 'trackhub');

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

Action for /api/trackhub/create (PUT)

=cut

sub trackhub_create :Path('/api/trackhub/create') Args(0) ActionClass('REST') {
  my ($self, $c) = @_;

  # get the list of existing document IDs
  my $docs = $c->model('ElasticSearch')->query(index => 'test', type => 'trackhub');

  # determine the ID of the doc to create
  my $current_max_id = max( map { $_->{_id} } @{$docs->{hits}{hits}} );
  $c->stash( id =>  $current_max_id?$current_max_id + 1:1 ); 
}

sub trackhub_create_PUT {
  my ($self, $c) = @_;
  my $new_doc_data = $c->req->data;

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide a doc to create!")
    unless defined $new_doc_data;

  my $id = $c->stash()->{'id'};
  if ($id) {
    $c->model('ElasticSearch')->index(index   => 'test',
				      type    => 'trackhub',
				      id      => $id,
				      body    => $new_doc_data);

    # refresh the index
    $c->model('ElasticSearch')->indices->refresh(index => 'test');

  } else {
    $c->detach('/api/error', [ "Couldn't determine doc ID" ]);
  }

  $self->status_created( $c,
			 location => $c->uri_for( '/api/trackhub/' . $id )->as_string,
			 entity   => $c->model('ElasticSearch')->find( index => 'test',
								       type  => 'trackhub',
								       id    => $id));
}

=head2 trackhub 

Actions for /api/trackhub/:id (GET|POST|DELETE)

=cut

sub trackhub :Path('/api/trackhub') Args(1) ActionClass('REST') {
  my ($self, $c, $doc_id) = @_;

  my %args = 
    ( index => 'test',
      type  => 'trackhub',
      id    => $doc_id);

  # if the doc with that ID doesn't exist, ES throws exception
  # intercept but do nothing, as the GET method will handle
  # the situation in a REST appropriate way.
  eval { $c->stash(trackhub => $c->model('ElasticSearch')->find(%args)); };
}

=head2 trackhub_GET

Return trackhub document content for a document
with the specified ID

=cut

sub trackhub_GET {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{'trackhub'};
  if ($trackhub) {
    $self->status_ok($c, entity => $trackhub) if $trackhub;
  } else {
    $self->status_not_found($c, message => "Could not find trackhub $doc_id");    
  }
}

=head2 trackhub_POST

Update document content for a document
with the specified ID

=cut

sub trackhub_POST {
  my ($self, $c, $doc_id) = @_;
  
  # if the doc with that ID doesn't exist,
  # cannot update the doc
  return $self->status_bad_request($c, message => "Cannot update: document (ID: $doc_id) does not exist")
    unless $c->stash()->{'trackhub'};

  my $new_doc_data = $c->req->data;

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide a doc to modify!")
    unless defined $new_doc_data;

  #
  # Updates in Elasticsearch
  # http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/partial-updates.html
  #
  # Partial updates can be done through the update API, which accepts a partial document.
  # However, this just gets merged with the existing document, so the only way to actually
  # update a document is to retrieve it, change it, then reindex the whole document.
  #
  $c->model('ElasticSearch')->index(index   => 'test',
				    type    => 'trackhub',
				    id      => $doc_id,
				    body    => $new_doc_data);

  # refresh the index
  $c->model('ElasticSearch')->indices->refresh(index => 'test');

  $self->status_ok( $c,
		    entity   => $c->model('ElasticSearch')->find( index => 'test',
								  type  => 'trackhub',
								  id    => $doc_id));
  
}

=head2 trackhub_DELETE

Delete a document with the specified ID

=cut

sub trackhub_DELETE {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{'trackhub'};
  if ($trackhub) {
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
    $c->model('ElasticSearch')->delete(index   => 'test',
				       type    => 'trackhub',
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

