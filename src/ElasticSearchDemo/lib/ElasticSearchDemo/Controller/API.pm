package ElasticSearchDemo::Controller::API;
use Moose;
use namespace::autoclean;

use List::Util 'max';

BEGIN { extends 'Catalyst::Controller::REST'; }

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
  $c->stash( id => max( map { $_->{_id} } @{$docs->{hits}{hits}} ) + 1 ); 
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
  } else {
    $c->detach('error', [500, 'Couldn\'t determine doc ID']);
  }

  $self->status_created( $c,
			 location => $c->uri_for( '/api/trackhub/' . $id )->as_string,
			 entity   => $c->model('ElasticSearch')->find( index => 'test',
								       type  => 'trackhub',
								       id    => $id));
}

=head2 trackhub 

Actions for /api/trackhub/:id (GET|POST)

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
  return $self->status_bad_request($c, message => "Cannot update: document (ID: $doc_id) doesn't exist")
    unless $c->stash()->{'trackhub'};

  my $new_doc_data = $c->req->data;

  # if the client didn't supply any data, 
  # they didn't send a properly formed request
  return $self->status_bad_request($c, message => "You must provide a doc to modify!")
    unless defined $new_doc_data;

  
}

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
sub error :Private {
  my ( $self, $c, $code, $reason ) = @_;
  $reason ||= 'Unknown Error';
  $code ||= 500;
 
  $c->res->status($code);
  # Error text is rendered as JSON as well
  $c->stash->{data} = { error => $reason };
}

=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

