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

=cut

package TestApp::Controller::Root;

use Moose 2.00;

BEGIN { extends 'Catalyst::Controller' }

__PACKAGE__->config(namespace => '');

sub user_login : Global {
  my ( $self, $c ) = @_;

  ## this allows anyone to login regardless of status.
  eval {
    $c->authenticate({ username => $c->request->params->{'username'},
		       password => $c->request->params->{'password'}
		     });
    1;
  } or do {
    return $c->res->body($@);
  };

  if ( $c->user_exists ) {
    if ( $c->req->params->{detach} ) {
      $c->detach( $c->req->params->{detach} );
    }
    $c->res->body( $c->user->get('username') . ' logged in' );
  } else {
    $c->res->body( 'not logged in' );
  }
}


sub user_logout : Global {
  my ( $self, $c ) = @_;

  $c->logout;

  if ( ! $c->user ) {
    $c->res->body( 'logged out' );
  } else {
    $c->res->body( 'not logged ok' );
  }
}

sub get_session_user : Global {
  my ( $self, $c ) = @_;

  if ( $c->user_exists ) {
    $c->res->body($c->user->get('username')); # . " " . Dumper($c->user->get_columns()) );
  }
}

sub is_admin : Global {
  my ( $self, $c ) = @_;

  eval {
    if ( $c->assert_user_roles( qw/admin/ ) ) {
      $c->res->body( 'ok' );
    }
  };
  if ($@) {
    $c->res->body( 'failed' );
  }
}

sub is_admin_user : Global {
  my ( $self, $c ) = @_;

  eval {
    if ( $c->assert_user_roles( qw/admin user/ ) ) {
      $c->res->body( 'ok' );
    }
  };
  if ($@) {
    $c->res->body( 'failed' );
  }
}

sub show_user_class : Global {
  my ( $self, $c ) = @_;

  $c->res->body(ref($c->user));
}

sub set_usersession : Global {
  my ( $self, $c, $value ) = @_;
  $c->user_session->{foo} = $value;
  $c->res->body( 'ok' );
}

sub get_usersession : Global {
  my ( $self, $c ) = @_;
  $c->res->body( $c->user_session->{foo} || '' );
}

sub get_auth_key : Global {
  my ($self, $c) = @_;

  $c->user->auth_key( $c->request->params->{'auth_token'} );
  $c->res->body( $c->user->get('auth_key') );
}

sub auth_key_access : Global {
  my ($self, $c) = @_;

  if ($c->authenticate({ username => $c->request->params->{'username'},
			 auth_key => $c->request->params->{'auth_key'}
		       }, 'usersauthkey')) {
    $c->res->body( $c->user->get('username') . ' authenticated with key' );
  } else {
    $c->res->body( 'user not key authenticated' );
  }

}

__PACKAGE__->meta->make_immutable;

1;
