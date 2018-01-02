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

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Controller::User - A Catalyst controller for authenticated user actions

=head1 DESCRIPTION

This is a controller providing actions for various URLs which provide the
front-end for authenticated users performing some administrative actions,
e.g. changing profile, list/view/delete trackhubs.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut


package Registry::Controller::User;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::ActionRole'; }

use Data::Dumper;
use List::Util 'max';
use Try::Tiny;
use Registry::Form::User::Registration;
use Registry::Form::User::Profile;
use Registry::TrackHub::TrackDB;

has 'registration_form' => ( isa => 'Registry::Form::User::Registration', is => 'rw',
    lazy => 1, default => sub { Registry::Form::User::Registration->new } );

=head1 METHODS

=head2 base

This is the action on top of a chain of actions which capture user information
after he/she has authenticated in the system. It puts the user ID and information
in the stash which can be used by the following methods in the chain.

=cut

sub base : Chained('/login/required') PathPrefix CaptureArgs(1) {
  my ($self, $c, $username) = @_;

  # retrieve user's data to show the profile
  #
  # since the user's logged in, it should be possible to
  # call Catalyst::Authentication::Store::ElasticSearch::User method, 
  # i.e. $user->get('..'), $user->id
  # without looking directly into the persistence engine
  # 
  # NOTE
  # Yes, but if the user changes its profile, then switches between 
  # the various tabs, and then comes back to the profile, session
  # data kicks in and it will show information before the update
  #
  # Catalyst::Exception->throw("Unable to find logged in user info")
  #     unless $c->user_exists;

  # $c->stash(user => $c->user->get_object()->{_source},
  # 	    id   => $c->user->id);

  my $config = Registry->config()->{'Model::Search'};
  my $query = { term => { username => $username } };
  my $user_search = $c->model('Search')->search( index => $config->{user}{index},
						 type  => $config->{user}{type},
						 body => { query => $query } );

  $c->stash(user => $user_search->{hits}{hits}[0]{_source},
  	    id   => $user_search->{hits}{hits}[0]{_id});

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
  my $profile_form = Registry::Form::User::Profile->new(init_object => $c->stash->{user});

  $c->stash(template => "user/profile.tt",
	    form     => $profile_form);
  
  return unless $profile_form->process( params => $c->req->parameters );

  # new profile validated, merge old with new profile
  # when attributes overlap overwrite the old entries with the new ones
  my $new_user_profile = $c->stash->{user};
  map { $new_user_profile->{$_} = $profile_form->value->{$_} } keys %{$profile_form->value};
  
  # update user profile on the backend
  my $config = Registry->config()->{'Model::Search'};
  $c->model('Search')->index(index   => $config->{user}{index},
			     type    => $config->{user}{type},
			     id      => $c->stash->{id},
			     body    => $new_user_profile);

  $c->model('Search')->indices->refresh(index => $config->{user}{index});

  $c->stash(status_msg => 'Profile updated');
}

=head2 delete

Action for the /user/admin/delete/:id URL which allows the admin user to delete
a user having the specified ID.

=cut

sub delete : Chained('base') Path('delete') Args(1) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c, $id) = @_;

  Catalyst::Exception->throw("Unable to find user id")
      unless defined $id;

  my $config = Registry->config()->{'Model::Search'};

  #
  # delete all trackDBs which belong to the user
  #
  # find username
  my $username = $c->model('Search')->search(index => $config->{user}{index},
					     type  => $config->{user}{type},
					     body  => {
						       query => { filtered => { filter => { bool => { must => [ { term => { _id => $id } } ] } } } }
						      }
					    )->{hits}{hits}[0]{_source}{username};
  Catalyst::Exception->throw("Unable to find user $id information")
      unless defined $username;

  # find trackDBs which belong to user
  my $query = { term => { owner => $username } };
  # my $query = { filtered => { filter => { bool => { must => [ { term => { owner => lc $username } } ] } } } };
  my $user_trackdbs = $c->model('Search')->search_trackhubs(query => $query, size => 100000);
  # my $user_trackdbs = grep { $_->{_source}{owner} eq $username } @{$c->model('Search')->search_trackhubs(query => $query, size => 100000)};

  $c->log->debug(sprintf "Found %d trackDBs for user %s (%s)", scalar @{$user_trackdbs->{hits}{hits}}, $id, $username);
  # delete user trackDBs
  foreach my $trackdb (@{$user_trackdbs->{hits}{hits}}) {
    $c->model('Search')->delete(index   => $config->{trackhub}{index},
				type    => $config->{trackhub}{type},
				id      => $trackdb->{_id});
    $c->log->debug(sprintf "Document %s deleted", $trackdb->{_id});
  }
  $c->model('Search')->indices->refresh(index => $config->{trackhub}{index});

  # delete the user
  $c->model('Search')->delete(index   => $config->{user}{index},
			      type    => $config->{user}{type},
			      id      => $id);
  $c->model('Search')->indices->refresh(index => $config->{user}{index});

  # redirect to the list of providers page
  # $c->detach('list_providers', [$c->stash->{user}{username}]);
  $c->res->redirect($c->uri_for($c->controller->action_for('list_providers', [$c->stash->{user}{username}])));
}

=head2 list_trackhubs

Action for /user/:user/list_trackhubs URL which shows an authenticated user the list
of trackhubs he/she has submitted to the system.

=cut

sub list_trackhubs : Chained('base') :Path('trackhubs') Args(0) {
  my ($self, $c) = @_;

  my $trackdbs;
  foreach my $trackdb (@{$c->model('Search')->get_trackdbs(query => { term => { owner => $c->user->username } })}) {
    push @{$trackdbs}, Registry::TrackHub::TrackDB->new($trackdb->{_id});
  }

  $c->stash(trackdbs => $trackdbs,
	    template  => "user/trackhub/list.tt");
}

=head2 submit_trackhubs

Action for /user/:user/submit_trackhubs URL which, at the moment, shows an authenticated user
how he/she might submit/update trackhubs to the system. In the future, we might want to provide
a form allowing the user to submit/update trackhubs directly from the web.

=cut

sub submit_trackhubs : Chained('base') :Path('submit_trackhubs') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template  => "user/trackhub/submit_update.tt");
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
  $c->stash(trackdb => $trackdb, template  => "user/trackhub/view.tt");
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

  $c->res->redirect($c->uri_for($c->controller->action_for('list_trackhubs', [$c->user->username])));
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
      my $config = Registry->config()->{'Model::Search'};
      # try { # TODO: this is not working for some reason
	$c->model('Search')->delete(index   => $config->{trackhub}{index},
				    type    => $config->{trackhub}{type},
				    id      => $id);
	$c->model('Search')->indices->refresh(index => $config->{trackhub}{index});
      # } catch {
      # 	Catalyst::Exception->throw($_);
      # };
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

  # get all user info, attach id
  my $users;
  # map { push @{$users}, $_->{_source} }
  #   @{$c->model('Search')->query(index => 'test', type => 'user')->{hits}{hits}};

  my $config = Registry->config()->{'Model::Search'};
  foreach my $user_data (@{$c->model('Search')->search(index => $config->{user}{index}, 
						       type  => $config->{user}{type},
						       size => 100000)->{hits}{hits}}) {
    my $user = $user_data->{_source};
    # don't want to show admin user to himself
    next if $user->{username} eq 'admin';
    $user->{id} = $user_data->{_id};
    push @{$users}, $user;
  }

  my $columns = [ 'username', 'first_name', 'last_name', 'fullname', 'email', 'affiliation' ];

  $c->stash(users     => $users,
	    columns   => $columns,
	    template  => "user/list.tt");

}

=head2 register

Action for /user/register URL presenting a form for signing up in the system.

=cut

sub register :Path('register') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template => "user/register.tt",
	    form     => $self->registration_form);

  return unless $self->registration_form->process( params => $c->req->parameters );

  # user input is validated
  # look if there's already a user with the provided username
  my $username = $self->registration_form->value->{username};
  # NOTE:
  # there are problems at the moment with with usernames containing
  # upper case characters. Deny registration in this case.
  if ($username =~ /[A-Z]/) {
    $c->stash(error_msg => "Username should not contain upper case characters.");
  } else {
    my $config = Registry->config()->{'Model::Search'};

    my $query = { term => { username => $username } };
    my $user_exists = 
      $c->model('Search')->count(index    => $config->{user}{index},
				 type     => $config->{user}{type},
				 body => { query => $query } )->{count};
  
    unless ($user_exists) {
      # user with the provided username does not exist, proceed with registration
    
      # get the max user ID to assign the ID to the new user
      my $users = $c->model('Search')->search(index => $config->{user}{index}, type => $config->{user}{type}, size => 100000);
      my $current_max_id = max( map { $_->{_id} } @{$users->{hits}{hits}} );

      # add default user role to user 
      my $user_data = $self->registration_form->value;
      $user_data->{roles} = [ 'user' ];

      $c->model('Search')->index(index => $config->{user}{index},
				 type  => $config->{user}{type},
				 id      => $current_max_id?$current_max_id + 1:1,
				 body    => $user_data);

      # refresh the index
      $c->model('Search')->indices->refresh(index => $config->{user}{index});

      # authenticate and redirect to the user profile page
      if ($c->authenticate({ username => $username,
			     password => $self->registration_form->value->{password} } )) {
	$c->stash(status_msg => sprintf "Welcome user %s", $username);
	$c->res->redirect($c->uri_for($c->controller('User')->action_for('profile'), [$username]));
	$c->detach;
      } else {
	# Set an error message
	$c->stash(error_msg => "Bad username or password.");
      }

    } else {
      # user with the provided username already exists
      # present the registration form again with the error message
      $c->stash(error_msg => "User $username already exists. Please choose a different username.");
    }    
  }

}

# sub admin : Chained('base') PathPart('') CaptureArgs(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {}

# sub list : Chained('admin') PathPart('user/list') Args(0) {
#   my ($self, $c) = @_;
 
#   # my $users = $c->model('DB::User')->search(
#   # 					    { active => 'Y'},
#   # 					    {
#   # 					     order_by => ['username'],
#   # 					     page     => ($c->req->param('page') || 1),
#   # 					     rows     => 20,
#   # 					    }
#   # 					   );
  
#   $c->stash(
#   	    users => $users,
#   	    pager => $users->pager,
#   	   );
  
# }

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
