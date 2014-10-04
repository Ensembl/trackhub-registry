package ElasticSearchDemo::Controller::API;
use Moose;
use namespace::autoclean;

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

Return list of available documents

Action for GET /api/trackhub, no arguments

Returns documents IDs mapped to the URI of the
resource which represents the document

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

#
# trackhub: return trackhub doc by id
#
# Action for GET /api/trackhub/:id
#
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

sub trackhub_GET {
  my ($self, $c, $doc_id) = @_;

  my $trackhub = $c->stash()->{'trackhub'};
  if ($trackhub) {
    $self->status_ok($c, entity => $trackhub) if $trackhub;
  } else {
    $self->status_not_found($c, message => "Could not find trackhub $doc_id");    
  }
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
 
# # We use the error action to handle errors
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

