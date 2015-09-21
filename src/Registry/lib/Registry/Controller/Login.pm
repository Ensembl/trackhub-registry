package Registry::Controller::Login;
use Moose;

use namespace::autoclean;

BEGIN { extends 'CatalystX::SimpleLogin::Controller::Login' }
 
sub do_post_login_redirect {
  my ($self, $ctx) = @_;
  $ctx->res->redirect($ctx->uri_for($ctx->controller('User')->action_for('list_trackhubs'), [$ctx->user->username]));
}
 
1;
