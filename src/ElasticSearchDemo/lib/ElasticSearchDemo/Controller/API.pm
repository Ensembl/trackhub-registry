package ElasticSearchDemo::Controller::API;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

__PACKAGE__->config(
  action => {
    '*' => {
      # Attributes common to all actions
      # in this controller
      Consumes => 'JSON',
      Path => '',
    }
  }
);

=head1 NAME

ElasticSearchDemo::Controller::API - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  #########################################################################
  # # Get the username and password from form
  # my $username = $c->request->params->{username} || "";
  # my $password = $c->request->params->{password} || "";
    
  # # If the username and password values were found in form
  # if ($username && $password) {
  #   # Attempt to authenticate the user
  #   if ($c->authenticate({ username => $username,
  #                          password => $password} )) {
  #     # If successful, then let them use the application
  #     $c->response->redirect($c->uri_for('/'));
  #     return;
  #   } else {
  #     # Set an error message
  #     $c->stash->{error_msg} = "Bad username or password.";
  #   }
  # }
    
  # # If either of above don't work out, send to the login page
  # $c->stash->{template} = 'login.tt';
  #########################################################################

  # # $c->response->body('Matched ElasticSearchDemo::Controller::API in API.');

  #
  # Abort request, as there's nothing available at the moment
  #
  # comment if you want to just proceed to the end method
  # and generate an empty successful response
  #
  my $username = $c->request->params->{username} || "";
  my $password = $c->request->params->{password} || "";
  if ($username && $password) {
    # Attempt to authenticate the user
    if ($c->authenticate({ username => $username,
                           password => $password} )) {
      # return welcome message
      $c->stash->{data} = { msg => "Welcome user $username" };
      return;
    } else {
      # Set an error message
      $c->detach('error', [ 401, 'Unauthorized' ]);
    }
  } 

  $c->detach('error', [401, 'Please specify username/password credentials']);
}

# end action is always called at the end of the route
sub end :Private {
  my ( $self, $c ) = @_;

  # Render the stash using our JSON view
  $c->forward($c->view('JSON'));
}
 
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

__PACKAGE__->meta->make_immutable;

1;
