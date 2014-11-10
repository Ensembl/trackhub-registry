package ElasticSearchDemo::Controller::User;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::ActionRole'; }

=head1 NAME

ElasticSearchDemo::Controller::User - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub base : Chained('/login/required') PathPart('') CaptureArgs(0) {}

sub admin : Chained('base') PathPart('') CaptureArgs(0) Does('ACL') RequiresRole('admin') ACLDetachTo('denied') {}

sub list : Chained('admin') PathPart('user/list') Args(0) {
  my ($self, $c) = @_;
 
  # my $users = $c->model('DB::User')->search(
  # 					    { active => 'Y'},
  # 					    {
  # 					     order_by => ['username'],
  # 					     page     => ($c->req->param('page') || 1),
  # 					     rows     => 20,
  # 					    }
  # 					   );
  
  # $c->stash(
  # 	    users => $users,
  # 	    pager => $users->pager,
  # 	   );
  
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
