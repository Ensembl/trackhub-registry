=head1 LICENSE

Copyright [2015-2020] EMBL-European Bioinformatics Institute

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

=head1 NAME

Registry::Controller::User - A Catalyst controller for authenticated user actions

=head1 DESCRIPTION

This is a controller providing actions for various URLs which provide the
front-end for authenticated users performing some administrative actions,
e.g. changing profile, list/view/delete trackhubs.

=cut


package Registry::Controller::User;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use Try::Tiny;
use Registry::Form::User::Registration;
use Registry::Form::User::Profile;
use Registry::TrackHub::TrackDB;

has registration_form => (
  isa => 'Registry::Form::User::Registration',
  is => 'rw',
  lazy => 1,
  default => sub { Registry::Form::User::Registration->new }
);

=head1 METHODS

=head2 login_submit

Provide a login form to the user. CatalystX::SimpleLogin can go away

=cut

sub login_request :Path('/login') GET {
  my ($self, $c) = @_;
  if (! $c->user_exists ) {
    $c->stash(
      template => 'login/login.tt'
    );
    $c->detach();
  } else {
    $c->forward($c->controller->action_for('list_trackhubs'));
  }
}

=head2 login_submit

Authenticate user. CatalystX::SimpleLogin just made things worse for preventing URL params
including user passwords.

=cut

sub login_submit :Path('/login') POST {
  my ($self, $c) = @_;
  
  my $authorized = $c->authenticate({
    username => $c->req->body_parameters->{username},
    password => $c->req->body_parameters->{password}
  }, 'web');

  if (!$authorized) {
    $c->log->debug('Authentication failed.');
    $c->stash(
      error_msg => 'Incorrect user name or password',
      template => 'login/login.tt'
    );
  } else {
    $c->log->debug('User logged in');

    # Now the user is authentic, we can put the user in the session for user-based operations in
    # logged in operations
    
    $c->session->{user} = $c->user;
    $c->session->{user_id} = $c->user->user_id;
    # At this point the user is logged in. Give the login page instructions for where to go now
    # We can't use redirect like the old version, because the client is too smart and sends its
    # payload to the list_trackhubs endpoint. It doesn't understand what to do.

    $c->forward($c->controller->action_for('list_trackhubs'));
  }
}


=head2 logout

De-authenticate user and clear session

=cut

sub logout : Path('/logout') {
  my ($self, $c) = @_;
  $c->logout();
  $c->delete_session('Logged out');
  $c->res->redirect(
    $c->uri_for('/')
  );
  $c->detach;
}

=head2 user

The root of the user account URLs. An opportunity to prepare some general user state
if necessary. Mainly we're maintaining the previous URL structure

=cut

sub user :Chained('/') :PathPart('user') CaptureArgs(0) {
  my ($self, $c) = @_;

  if (!$c->user_exists) {
    $c->log->debug('User accessed page without logging in');
    $c->stash(status_msg => 'You need to be logged in to access these pages');
    $c->response->redirect($c->uri_for('/login'));
    $c->detach;
  }

  return;
}

=head2 profile

Action for the /user/profile URL, which presents the form to change 
the user's profile.

=cut

sub profile :Chained('user') :PathPart('profile') Args(0) {
  my ($self, $c) = @_;
  
  # complain if user has not been found
  if (! exists $c->session->{user}) {
    Catalyst::Exception->throw('Unable to find user information in session');
  }

  # Fill in form with user data
  my $profile_form = Registry::Form::User::Profile->new(item => $c->session->{user});

  $c->stash(
    template => "user/profile.tt",
    form     => $profile_form
  );
  
  return unless $profile_form->process( params => $c->req->parameters );

  $c->session->{user}->update;


  $c->stash(status_msg => 'Profile updated');
}

=head2 delete

Action for the /user/admin/delete/:id URL which allows the admin user to delete
a user having the specified ID.

=cut

sub delete : Chained('user') PathPart('delete') Args(1) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c, $username) = @_;

  Catalyst::Exception->throw('No user name specified') unless defined $username;

  my $user = $c->model('Users')->get_user($username);
  if (! defined $user ) {
    Catalyst::Exception->throw('Unable to find user $username information');
  }

  my $user_trackdbs = $c->model('Search')->get_hubs_by_user_name($username);

  $c->log->debug(sprintf 'Found %d trackDBs for user %s', scalar @{$user_trackdbs}, $username);
  # delete user trackDBs
  foreach my $trackdb (@{$user_trackdbs}) {
    $c->model('Search')->delete_hub_by_id($trackdb->{_id});
    $c->log->debug(sprintf "Document %s deleted", $trackdb->{_id});
  }
  $c->model('Search')->refresh_trackhub_index;

  # delete the user by ID
  $c->model('Users')->delete_user($user);

  # redirect to the list of providers page
  $c->res->redirect(
    $c->uri_for(
      $c->controller->action_for(
        'list_providers'
      )
    )
  );
}

=head2 list_trackhubs

Action for /user/trackhubs URL which shows an authenticated user the list
of trackhubs he/she has submitted to the system.

=cut

sub list_trackhubs :Chained('user') :PathPart('trackhubs') :Args(0) {
  my ($self, $c) = @_;
  if (! $c->user_exists) {
    $c->log->debug('Got here without a login. Be on your way');
    $c->detach('denied');
  }

  my $trackdbs;
  my $hubs_for_user = $c->model('Search')->get_hubs_by_user_name($c->user->username);

  foreach my $trackdb (@{$hubs_for_user}) {
    push @{$trackdbs}, Registry::TrackHub::TrackDB->new(doc => $trackdb->{_source}, id => $trackdb->{_id});
  }

  $c->stash(
    trackdbs => $trackdbs,
    template => 'user/trackhub/list.tt'
  );
}

=head2 submit_trackhubs

Action for /user/submit_trackhubs URL which, at the moment, shows an authenticated user
how he/she might submit/update trackhubs to the system. In the future, we might want to provide
a form allowing the user to submit/update trackhubs directly from the web.

=cut

sub submit_trackhubs :Chained('user') :PathPart('submit_trackhubs') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template => 'user/trackhub/submit_update.tt');
}

=head2 view_trackhub_status

Action for /user/view_trackhub_status/:id allowing an authenticated user to view
the status of a trackdb having the given id in the back end.

=cut

sub view_trackhub_status :Chained('user') :PathPart('view_trackhub_status') :Args(1) {
  my ($self, $c, $id) = @_;
  my $hub = $c->model('Search')->get_trackhub_by_id($id, 1);
  $c->log->debug('Retrieved hub '.$id);
  if ($c->req->params->{toggle_search}) {
    $hub = $c->model('Search')->toggle_search($id, $hub);
  }
  my $trackdb = Registry::TrackHub::TrackDB->new(doc => $hub, id => $id);
  $c->stash(
    trackdb => $trackdb,
    template => 'user/trackhub/view.tt'
  );
  $c->log->debug('Set template to view.tt');
  $c->detach;
}

=head2 refresh_trackhub_status

Action for /user/refresh_trackhub_status/:id allowing an authenticated user to
refresh the status of a trackdb having the given id. This triggers the system to perform
a check on the availability of the remote files specified in the trackdb.

NOTE: this is not shown on the current front-end as it can take a very long time in case
the trackdb references a very large number of remote files.

=cut

sub refresh_trackhub_status : Chained('user') :PathPart('refresh_trackhub_status') Args(1) {
  my ($self, $c, $id) = @_;

  try {
    my $hub = $c->model('Search')->get_trackhub_by_id($id);
    $c->model('Search')->update_status($hub);
  } catch {
    $c->stash(error_msg => $_);
  };

  $c->res->redirect(
    $c->uri_for(
      $c->controller->action_for(
        'list_trackhubs',
        [$c->user->username]
      )
    )
  );
  $c->detach;
}

=head2 delete_trackhub

Action for /user/delete_trackhub/:id allowing an authenticated user to delete a trackdb by id.

=cut

sub delete_trackhub : Chained('user') :PathPart('delete') Args(1) {
  my ($self, $c, $id) = @_;
  $c->log->debug("Going to delete $id");
  my $doc = $c->model('Search')->get_trackhub_by_id($id);

  if ($doc) {
    # TODO: this should be redundant, but just to be sure
    if ($doc->{_source}{owner} eq $c->user->username) {
      
      $c->model('Search')->delete_hub_by_id($id);
      $c->model('Search')->refresh_trackhub_index;
      
      $c->stash(status_msg => "Deleted track collection [$id]");
    } else {
      $c->log->debug('Failed to delete, because owner of hub and user do not match');
      # TODO: these error message don't render in the template
      $c->stash(error_msg => "Cannot delete collection [$id], does not belong to you");
    }
  } else {
    $c->stash(error_msg => "Could not fetch track collection [$id]");
  }

  $c->res->redirect($c->uri_for($c->controller->action_for('list_trackhubs', [$c->user->username])));
  $c->detach;
}

=head2 list_providers

Action for /user/providers URL used by the administrator to show the list of authenticated
users who have submitted trackhubs to the system.

=cut

sub list_providers : Chained('user') PathPart('providers') Args(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c) = @_;

  # get all user info. Don't want to show admin user to himself
  my $users = [ grep { $_->{username} ne 'admin' } @{$c->model('Users')->get_all_users()} ];

  my $columns = [ 'username', 'first_name', 'last_name', 'fullname', 'email', 'affiliation' ];

  $c->stash(
    users     => $users,
    columns   => $columns,
    template  => 'user/list.tt'
  );

}

=head2 register

Action for /user/register URL presenting a form for signing up in the system.

=cut

sub register :Path('register') Args(0) {
  my ($self, $c) = @_;

  $c->stash(
    template => "user/register.tt",
    form     => $self->registration_form  # Keep form state for next page view
  );

  my $status = $self->registration_form->process(
    params => $c->req->parameters
  );
  if ($status) {
    try {

      my $user_params = $self->registration_form->value;

      delete $user_params->{password_conf};
      delete $user_params->{gdpr_accept};
      # It might be better if this password were encoded client side
      my $plain_password = $user_params->{password};
      $user_params->{password} = $c->model('Users')->encode_password($user_params->{password});

      my $new_user = $c->model('Users::User')->create($user_params);
      $new_user->add_to_roles({ name => 'user' });

      $c->log->debug('New user registered:'.$new_user->username);

      $c->log->debug(sprintf 'Attempt to authenticate new user: %s : %s', $new_user->username, $plain_password);
      # Log the new user in for them
      if ($c->authenticate({
          username => $new_user->username,
          password => $plain_password
        }, 'web')
      ) {
        $c->stash(status_msg => 'Welcome user '.$new_user->username);
        $c->session->{user} = $new_user;
        $c->session->{user_id} = $new_user->user_id;
        $c->forward($c->controller->action_for('profile'));
      } else {
        throw('Failed to authenticate new user account.');
      }
    } catch {
      if ($_ =~ m/UNIQUE/) {
        $c->stash(error_msg => 'User name is already in use. Please choose a different username.');
      } else {
        $c->stash(error_msg => "Failed to register new user account. Contact Trackhub Registry administrators with error: $_");
      }
    };
  } elsif ($self->registration_form->has_errors) {
    $c->stash(error_msg => "Form validation failed in the following fields:\n". join "\n",$self->registration_form->errors);
  }

}

=head2 denied

Redirect to the login page with an error message if a user fails to authenticate.

=cut

sub denied : Private {
  my ($self, $c) = @_;
 
  $c->stash(
    status_msg => 'Access Denied',
    template   => 'login/login.tt'
  );
}

__PACKAGE__->meta->make_immutable;

1;
