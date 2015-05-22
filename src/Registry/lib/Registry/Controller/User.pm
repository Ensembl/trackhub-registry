package Registry::Controller::User;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::ActionRole'; }
# BEGIN { extends 'Catalyst::Controller' }

use Data::Dumper;
use List::Util 'max';
use Try::Tiny;
use Registry::Form::User::Registration;
use Registry::Form::User::Profile;
use Registry::TrackHub::TrackDB;

=head1 NAME

Registry::Controller::User - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

has 'registration_form' => ( isa => 'Registry::Form::User::Registration', is => 'rw',
    lazy => 1, default => sub { Registry::Form::User::Registration->new } );

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
  my $user_search = $c->model('Search')->search( index => $config->{index},
						 type  => $config->{type}{user},
						 body => { query => $query } );

  $c->stash(user => $user_search->{hits}{hits}[0]{_source},
  	    id   => $user_search->{hits}{hits}[0]{_id});

}

#
# Change user profile
#
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
  $c->model('Search')->index(index   => $config->{index},
			     type    => $config->{type}{user},
			     id      => $c->stash->{id},
			     body    => $new_user_profile);

  $c->model('Search')->indices->refresh(index => $config->{index});

  $c->stash(status_msg => 'Profile updated');
}

#
# Admin deletes a user
#
sub delete : Chained('base') Path('delete') Args(1) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c, $id) = @_;

  Catalyst::Exception->throw("Unable to find user id")
      unless defined $id;

  my $config = Registry->config()->{'Model::Search'};
  $c->model('Search')->delete(index   => $config->{index},
			      type    => $config->{type}{user},
			      id      => $id);
  $c->model('Search')->indices->refresh(index => $config->{index});

  # redirect to the list of providers page
  $c->detach('list_providers', [$c->stash->{user}{username}]);
}

#
# List all available trackhubs for a given user
#
sub list_trackhubs : Chained('base') :Path('trackhubs') Args(0) {
  my ($self, $c) = @_;

  my $trackdbs;
  my $query = { term => { owner => $c->user->username } };

  foreach my $doc (@{$c->model('Search')->search_trackhubs(size => 1000000, query => $query)->{hits}{hits}}) {
    push @{$trackdbs}, Registry::TrackHub::TrackDB->new($doc->{_id});
  }

  $c->stash(trackdbs => $trackdbs,
	    template  => "user/trackhub/list.tt");
}

sub submit_trackhubs : Chained('base') :Path('submit_trackhubs') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template  => "user/trackhub/submit_update.tt");
}

sub view_trackhub_status : Chained('base') :Path('view_trackhub_status') Args(1) {
  my ($self, $c, $id) = @_;

  my $trackdb;
  try {
    $trackdb = Registry::TrackHub::TrackDB->new($id);
  } catch {
    $c->stash(error_msg => $_);
  };

  $c->stash(trackdb => $trackdb, template  => "user/trackhub/view.tt");
}

sub refresh_trackhub_status : Chained('base') :Path('refresh_trackhub_status') Args(1) {
  my ($self, $c, $id) = @_;

  try {
    my $trackdb = Registry::TrackHub::TrackDB->new($id);
    $trackdb->update_status();
  } catch {
    $c->stash(error_msg => $_);
  };

  $c->forward('list_trackhubs', [ $c->user->username ]);
}

sub delete_trackhub : Chained('base') :Path('delete') Args(1) {
  my ($self, $c, $id) = @_;
  
  my $doc = $c->model('Search')->get_trackhub_by_id($id);
  if ($doc) {
    # TODO: this should be redundant, but just to be sure
    if ($doc->{owner} eq $c->user->username) {
      my $config = Registry->config()->{'Model::Search'};
      # try { # TODO: this is not working for some reason
	$c->model('Search')->delete(index   => $config->{index},
				    type    => $config->{type}{trackhub},
				    id      => $id);
	$c->model('Search')->indices->refresh(index => $config->{index});
      # } catch {
      # 	Catalyst::Exception->throw($_);
      # };
      $c->stash(status_msg => sprintf("Deleted track collection [%d]", $id));
      $c->forward('list_trackhubs', [ $c->user->username ]);
    } else {
      $c->stash(error_msg => "Cannot delete collection [$id], does not belong to you");
    }
  } else {
    $c->stash(error_msg => "Could not fetch track collection [$id]");
  }

  # TODO: this is not properly working.
  #       address is still that of delete action,
  #       and list_trackhubs tab is not active
  $c->forward('list_trackhubs', [ $c->user->username ]);
}

#
# Admin lists all available trackhub providers
#
sub list_providers : Chained('base') Path('providers') Args(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c) = @_;

  # get all user info, attach id
  my $users;
  # map { push @{$users}, $_->{_source} }
  #   @{$c->model('Search')->query(index => 'test', type => 'user')->{hits}{hits}};

  my $config = Registry->config()->{'Model::Search'};
  foreach my $user_data (@{$c->model('Search')->search(index => $config->{index}, 
						       type  => $config->{type}{user},
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

sub register :Path('register') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template => "user/register.tt",
	    form     => $self->registration_form);

  return unless $self->registration_form->process( params => $c->req->parameters );

  # user input is validated
  # look if there's already a user with the provided username
  my $username = $self->registration_form->value->{username};
  my $query = { term => { username => $username } };
  my $user_exists = 
    $c->model('Search')->count( body => { query => $query } )->{count};
  
  unless ($user_exists) {
    # user with the provided username does not exist
    # proceed with registration
    
    # get the max user ID to assign the ID to the new user
    my $config = Registry->config()->{'Model::Search'};
    my $users = $c->model('Search')->search(index => $config->{index}, type => $config->{type}{user}, size => 100000);
    my $current_max_id = max( map { $_->{_id} } @{$users->{hits}{hits}} );

    # add default user role to user 
    my $user_data = $self->registration_form->value;
    $user_data->{roles} = [ 'user' ];

    $c->model('Search')->index(index => $config->{index},
			       type  => $config->{type}{user},
			       id      => $current_max_id?$current_max_id + 1:1,
			       body    => $user_data);

    # refresh the index
    $c->model('Search')->indices->refresh(index => $config->{index});

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

sub denied : Private {
  my ($self, $c) = @_;
 
  $c->stash(status_msg => "Access Denied",
	    template   => "login/login.tt");
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
