=head1 LICENSE

Copyright [2015-2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
  my $form = Registry::Form::User::Profile->new;
  $c->stash(form => $form);
}

sub admin : Chained('base') PathPart('') CaptureArgs(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {}


sub profile : Chained('base') PathPart('profile') Args(0) {
    my ($self, $c) = @_;

    my $form = Registry::Form::User::Profile->new;

    $c->stash(template => "user/profile.tt", form => $form);

    return unless $form->process(
        schema  => $c->model('DB')->schema,
        item_id => $c->user->id,
        params  => $c->req->body_parameters,
    );

	 $c->res->redirect($c->uri_for($c->controller('User')->action_for('list_trackhubs', {
        status_msg => 'Profile Updated'
    }), [$c->user->username]));
    
   
}


#
# Admin deletes a user
#
sub delete : Chained('base') Path('delete') Args(1) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c, $id) = @_;

  Catalyst::Exception->throw("Unable to find user id")
      unless defined $id;

  my $config = Registry->config()->{'Model::Search'};

  #
  # delete all trackDBs which belong to the user
  #
  # find username
  my $user = $c->model('DB::User')->find($id);
  my $username = $user->username;

  Catalyst::Exception->throw("Unable to find user $id information")
      unless defined $username;

  # find trackDBs which belong to user
  my $query = { term => { owner => $username } };
  my $user_trackdbs = $c->model('Search')->search_trackhubs(query => $query, size => 100000);
  
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
   
  $user->delete;
  
  # redirect to the list of providers page
  $c->res->redirect($c->uri_for($c->controller->action_for('list_providers', [$c->stash->{user}{username}])));
}

#TODO
sub change_password : Chained('base') PathPart('change_password') Args(0) {
    my ($self, $c) = @_;

    my $form = Registry::Form::ChangePassword->new;

    $c->stash(form => $form);

    return unless $form->process(
        user   => $c->user,
        params => $c->req->body_parameters,
    );

    $c->user->update({
        password         => $form->field('new_password')->value,
        password_expires => undef,
    });

     $c->res->redirect($c->uri_for($c->controller('User')->action_for('list_trackhubs', {
        status_msg => 'Password changed successfully'
    }), [$c->user->username]));
}


sub user : Chained('admin') PathPart('') CaptureArgs(1) {
    my ($self, $c, $user_id) = @_;

    $c->stash(user => $c->model('DB::User')->find($user_id));
}

#
# List all available trackhubs for a given user
#
sub list_trackhubs : Chained('base') :Path('trackhubs') Args(0) {
  my ($self, $c) = @_;

  my $trackdbs;
  foreach my $trackdb (@{$c->model('Search')->get_trackdbs(query => { term => { owner => $c->user->username } })}) {
    push @{$trackdbs}, Registry::TrackHub::TrackDB->new($trackdb->{_id});
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

  $trackdb->toggle_search if $c->req->params->{toggle_search};
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

  $c->res->redirect($c->uri_for($c->controller->action_for('list_trackhubs', [$c->user->username])));
  $c->detach;
}

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

#
# Admin lists all available trackhub providers
#
sub list_providers : Chained('base') Path('providers') Args(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {
  my ($self, $c) = @_;

  # get all user info, attach id
  my $all_users = $c->model('DB::User')->search(
        { active => 'Y'},
        {
            order_by => ['username'],
            page     => ($c->req->param('page') || 1),
            rows     => 20,
        }
  );
   
  my $users;
  foreach my $user_data($all_users->all){
      push @{$users}, $user_data;
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
  # NOTE:
  # there are problems at the moment with with usernames containing
  # upper case characters. Deny registration in this case.
  if ($username =~ /[A-Z]/) {
    $c->stash(error_msg => "Username should not contain upper case characters.");
  } else {
    my $config = Registry->config()->{'Model::Search'};
    
    #check if user exists
    my $user_exists = $c->model('DB::User')->search( {username=>$username})->all;
    unless ($user_exists) {
     # user with the provided username does not exist, proceed with registration
      my $user_data = $self->registration_form->value;
      my $user = $c->model('DB::User')->create({
      	username => $user_data->{username},
      	password => $user_data->{password},
      	first_name => $user_data->{first_name},
      	last_name => $user_data->{last_name},
      	email_address => $user_data->{email},
      	check_interval => $user_data->{check_interval},
      	continuous_alert => $user_data->{continuous_alert},
      	affiliation => $user_data->{affiliation}
       });

      # authenticate and redirect to the user profile page
      
      if($user){
      	#Search roles table for role 'user'
      	my $user_role = $c->model('DB::Role')->single({name=>'user'});
      	# add default user role to user 
      	$user->add_to_user_roles({role_id => $user_role->id});
      }
      
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
