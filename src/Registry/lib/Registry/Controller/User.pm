=head1 LICENSE

Copyright [2015-2018] EMBL-European Bioinformatics Institute

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

BEGIN { extends 'Catalyst::Controller::ActionRole'; }

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

=head2 base

This is the action on top of a chain of actions which capture user information
after he/she has authenticated in the system. It puts the user ID and information
in the stash which can be used by the following methods in the chain.

=cut

sub base : Chained('/login/required') PathPrefix CaptureArgs(1) ACLDetachTo('denied') {
  my ($self, $c, $username) = @_;

  # retrieve user's data to show the profile

  $c->log->debug("Validate user $username has logged in");
  my $user = $c->model('Users')->get_user($username);
  $c->detach() if ! defined $user;
  $c->stash(
    user => $user,
    id   => $user->user_id
  );
}

=head2 profile

Action for the /user/:user/profile URL, which presents the form to change 
the user's profile.

=cut

sub profile : Chained('base') :Path('profile') Args(0) {
  my ($self, $c) = @_;
  
  # complain if user has not been found
  Catalyst::Exception->throw("Unable to find user information")
      unless defined $c->stash->{user};

  # Fill in form with user data
  my $profile_form = Registry::Form::User::Profile->new(item => $c->stash->{user});

  $c->stash(
    template => "user/profile.tt",
    form     => $profile_form
  );
  
  return unless $profile_form->process( params => $c->req->parameters );

  $c->stash(status_msg => 'Profile updated');
}

=head2 delete

Action for the /user/admin/delete/:id URL which allows the admin user to delete
a user having the specified ID.

=cut

sub delete : Chained('base') Path('delete') Args(1) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c, $username) = @_;

  Catalyst::Exception->throw("No user name specified") unless defined $username;

  #
  # delete all trackDBs which belong to the user
  #
  # find username

  my $user = $c->model('Users')->get_user($username);
  if (! defined $user ) {
    Catalyst::Exception->throw("Unable to find user $username information");
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
        'list_providers',
        [$c->stash->{user}{username}]
      )
    )
  );
}

=head2 list_trackhubs

Action for /user/:user/list_trackhubs URL which shows an authenticated user the list
of trackhubs he/she has submitted to the system.

=cut

sub list_trackhubs : Chained('base') :Path('trackhubs') Args(0) {
  my ($self, $c) = @_;

  my $trackdbs;
  my $hubs_for_user = $c->model('Search')->get_hubs_by_user_name($c->user->username);

  foreach my $trackdb (@{$hubs_for_user}) {
    push @{$trackdbs}, Registry::TrackHub::TrackDB->new($trackdb->{_id});
  }

  $c->stash(
    trackdbs => $trackdbs,
    template => "user/trackhub/list.tt"
  );
}

=head2 submit_trackhubs

Action for /user/:user/submit_trackhubs URL which, at the moment, shows an authenticated user
how he/she might submit/update trackhubs to the system. In the future, we might want to provide
a form allowing the user to submit/update trackhubs directly from the web.

=cut

sub submit_trackhubs : Chained('base') :Path('submit_trackhubs') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template => "user/trackhub/submit_update.tt");
}

=head2 view_trackhub_status

Action for /user/:user/view_trackhub_status/:id allowing an authenticated user to view
the status of a trackdb having the given id in the back end.

=cut

sub view_trackhub_status : Chained('base') :Path('view_trackhub_status') Args(1) {
  my ($self, $c, $id) = @_;

  my $trackdb;
  try {
    $trackdb = Registry::TrackHub::TrackDB->new($id);
  } catch {
    $c->stash(error_msg => $_);
  };

  $trackdb->toggle_search if $c->req->params->{toggle_search};
  $c->stash(trackdb => $trackdb, template => 'user/trackhub/view.tt');
}

=head2 refresh_trackhub_status

Action for /user/:user/refresh_trackhub_status/:id allowing an authenticated user to
refresh the status of a trackdb having the given id. This triggers the system to perform
a check on the availability of the remote files specified in the trackdb.

NOTE: this is not shown on the current front-end as it can take a very long time in case
the trackdb references a very large number of remote files.

=cut

sub refresh_trackhub_status : Chained('base') :Path('refresh_trackhub_status') Args(1) {
  my ($self, $c, $id) = @_;

  try {
    my $trackdb = Registry::TrackHub::TrackDB->new($id);
    $trackdb->update_status();
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

Action for /user/:user/delete_trackhub/:id allowing an authenticated user to delete a trackdb by id.

=cut

sub delete_trackhub : Chained('base') :Path('delete') Args(1) {
  my ($self, $c, $id) = @_;
  
  my $doc = $c->model('Search')->get_trackhub_by_id($id);
  if ($doc) {
    # TODO: this should be redundant, but just to be sure
    if ($doc->{owner} eq $c->user->username) {
      
      $c->model('Search')->delete_hub_by_id($id);
      $c->model('Search')->refresh_trackhub_index;
      
      $c->stash(status_msg => "Deleted track collection [$id]");
    } else {
      $c->stash(error_msg => "Cannot delete collection [$id], does not belong to you");
    }
  } else {
    $c->stash(error_msg => "Could not fetch track collection [$id]");
  }

  $c->res->redirect($c->uri_for($c->controller->action_for('list_trackhubs', [$c->user->username])));
  $c->detach;
}

=head2 list_providers

Action for /user/admin/list_providers URL used by the administrator to show the list of authenticated
users who have submitted trackhubs to the system.

=cut

sub list_providers : Chained('base') Path('providers') Args(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c) = @_;

  # get all user info. Don't want to show admin user to himself
  my $users = [ grep { $_->{username} ne 'admin' } @{$c->model('Users')->get_all_users()} ];

  my $columns = [ 'username', 'first_name', 'last_name', 'fullname', 'email', 'affiliation' ];

  $c->stash(
    users     => $users,
    columns   => $columns,
    template  => "user/list.tt"
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

      my $new_user = $self->model('Users::User')->create($self->registration_form->value);
      $c->model('Users')->encode_password($new_user);

      $new_user->add_to_roles({ name => 'user' });

      if ($c->authenticate({ 
          username => $new_user->username,
          password => $self->registration_form->value->{password} 
        })
      ) {
        $c->stash(status_msg => 'Welcome user '.$new_user->username);
        $c->res->redirect(
          $c->uri_for($c->controller('User')->action_for('profile'), [$new_user->username])
        );
        $c->detach;
      }
    } catch {
      if ($_ =~ m/already exists/) {
        $c->stash(error_msg => 'User name is already in use. Please choose a different username.');
      } else {
        $c->stash(error_msg => "Failed to register new user account. Contact Trackhub Registry administrators with error: $_");
      }
    };
  } else {
    $c->stash(error_msg => "Form validation failed in the following fields:\n". join "\n",$self->registration_form->errors);
  }

}

=head2 denied

Redirect to the login page with an error message if a user fails to authenticate.

=cut

sub denied : Private {
  my ($self, $c) = @_;
 
  $c->stash(status_msg => "Access Denied",
            template   => "login/login.tt");
}

__PACKAGE__->meta->make_immutable;

1;
