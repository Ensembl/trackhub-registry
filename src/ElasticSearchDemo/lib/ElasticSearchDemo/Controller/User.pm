package ElasticSearchDemo::Controller::User;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::ActionRole'; }

use List::Util 'max';
use ElasticSearchDemo::Form::User::Registration;

=head1 NAME

ElasticSearchDemo::Controller::User - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

has 'registration_form' => ( isa => 'ElasticSearchDemo::Form::User::Registration', is => 'rw',
    lazy => 1, default => sub { ElasticSearchDemo::Form::User::Registration->new } );

sub base : Chained('/login/required') PathPart('') CaptureArgs(0) {}

sub register :Path('/user/register') Args(0) {
  my ($self, $c) = @_;

  $c->stash(template => "user/register.tt",
	    form     => $self->registration_form);

  return unless $self->registration_form->process( params => $c->req->parameters );

  # use Data::Dumper;
  # $c->log->debug(Dumper($self->registration_form->fif));
  # $c->log->debug(Dumper($self->registration_form->value));

  # user input is validated
  # look if there's already a user with the provided username
  my $username = $self->registration_form->value->{username};
  my $query = { term => { username => $username } };
  my $user_exists = 
    $c->model('ElasticSearch')->count( body => { query => $query } )->{count};
  
  unless ($user_exists) {
    # user with the provided username does not exist
    # proceed with registration
    
    # get the max user ID to assign the ID to the new user
    my $users = $c->model('ElasticSearch')->query(index => 'test', type => 'user');
    my $current_max_id = max( map { $_->{_id} } @{$users->{hits}{hits}} );
    
    $c->model('ElasticSearch')->index(index   => 'test',
				      type    => 'user',
				      id      => $current_max_id?$current_max_id + 1:1,
				      body    => $self->registration_form->value);

    # refresh the index
    $c->model('ElasticSearch')->indices->refresh(index => 'test');

    # redirect to the user profile page
    

  } else {
    # user with the provided username already exists
    # present the registration form again with the error message
    $c->stash(error_msg => "User $username already exists. Please choose a different username.");
  }
}

sub admin : Chained('base') PathPart('') CaptureArgs(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {}

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
