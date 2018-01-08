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

#
# A storage class for Catalyst Authentication using ElasticSearch
# Strongly inspired by CouchDB storage authentication module
#
# See Catalyst::Authentication::Store::CouchDB 
#
package Catalyst::Authentication::Store::ElasticSearch;

use strict;
use warnings;

BEGIN {
  $Catalyst::Authentication::Store::ElasticSearch::VERSION = '0.001';
}

use Moose 2.00;
use Catalyst::Exception;

has 'store_user_class'  => (is => 'ro', isa => 'Str', default => 'Catalyst::Authentication::Store::ElasticSearch::User', );
has 'config'            => (is => 'ro', isa => 'HashRef', required => 1,  );

# Convert the parameters passed to ->new into the correct
# format for passing to our Moose generated constructor.
# Also, ensure that the user class is loaded.

around BUILDARGS => sub {
  my ( $orig, $class, $config, $c ) = @_;

  # figure out if we are overriding the default store user class
  $config->{'store_user_class'} = 
    (exists($config->{'store_user_class'})) ? $config->{'store_user_class'} :
      "Catalyst::Authentication::Store::ElasticSearch::User";

  # make sure the user class is loaded.
  Catalyst::Utils::ensure_class_loaded( $config->{'store_user_class'} );

  # # overrides 'nodes' parameter or set to ES default: localhost:9200
  $config->{'nodes'} = '127.0.0.1:9200'
    unless exists $config->{'nodes'};

  # # overrides 'transport' parameter or set to default
  # $config->{'transport'} = (exists($config->{'transport'})) ? $config->{'transport'} :
  #   "Search::Elasticsearch::Transport";
    
  # $orig will call the superclass BUILDARGS, which
  # will format the args hash appropriately.
  return $class->$orig(
		       store_user_class => $config->{store_user_class},
		       config => $config,
		      );
};

sub from_session {
  my ($self, $c, $frozenuser) = @_;

  my $user = $self->store_user_class->new($self->{'config'}, $c);
  return $user->from_session($frozenuser);
}

sub for_session {
  my ($self, $c, $user) = @_;

  return $user->for_session();
}

sub find_user {
  my ($self, $authinfo, $c) = @_;

  my $user = $self->store_user_class->new($self->{'config'}, $c);

  return $user->load($authinfo, $c);
}

sub user_supports {
  my $self = shift;

  # this can work as a class method on the user class
  return $self->store_user_class->supports( @_ );
}

1;



=pod

=head1 NAME

Catalyst::Authentication::Store::ElasticSearch - A storage class for Catalyst Authentication using ElasticSearch

=head1 VERSION

version 0.001

=head1 SYNOPSIS

    use Catalyst qw/
                    Authentication
                    Authorization::Roles/;

    __PACKAGE__->config->{authentication} =
                    {
                        default_realm => 'members',
                        realms => {
                            members => {
                                credential => {
                                    class => 'Password',
                                    password_field => 'password',
                                    password_type => 'salted_hash',
                                    password_salt_len => 4,
                                },
                                store => {
                                    class       => 'ElasticSearch',
                                    couchdb_uri => 'http://localhost:5984',
                                    dbname      => 'demouser',
                                    designdoc   => '_design/user',
                                    view        => 'user',
                                },
                            },
                        },
                    };

    # Log a user in:

    sub login : Global {
        my ( $self, $c ) = @_;

        $c->authenticate({
                          username => $c->req->params->{username},
                          password => $c->req->params->{password},
                          }))
    }

    # verify a role

    if ( $c->check_user_roles( 'editor' ) ) {
        # do editor stuff
    }

=head1 DESCRIPTION

The Catalyst::Authentication::Store::ElasticSearch class provides access to authentication
information stored in a ElasticSearch instance.

=head1 CONFIGURATION

The ElasticSearch authentication store is activated by setting the store
config's B<class> element to ElasticSearch as shown above. See the
L<Catalyst::Plugin::Authentication> documentation for more details on
configuring the store.

The ElasticSearch storage module has several configuration options

    __PACKAGE__->config->{authentication} =
                    {                      
                        default_realm => 'members',
                        realms => {
                            members => {
                                credential => {
                                    class => 'Password',
                                    password_field => 'password',
                                    password_type => 'clear'
                                },
                            store => {
                                class       => 'ElasticSearch',
                                couchdb_uri => 'http://localhost:5984',
                                dbname      => 'demouser',
                                designdoc   => '_design/user',
                                view        => 'user',
                            },
                        },
                    },
                };

=over 4

=item class

Class is part of the core Catalyst::Plugin::Authentication module; it
contains the class name of the store to be used.  This config item is B<REQUIRED>.

=item couchdb_uri

Contains the URI of the ElasticSearch instance to query.  This config item is B<REQUIRED>.

=item dbname

Contains the name of the database to query.  This config item is B<REQUIRED>.

=item designdoc

Contains the name of the ElasticSearch design document to query.  This config item is B<REQUIRED>.

=item view

Contains the name of the view in the design document to query.  The 'username' field
will be used as the key to query, and the first document retrieved will be used
to create the user model.  This config item is B<REQUIRED>.

=item ua

Contains the name of a class to be used for the User Agent.  This defaults
to LWP::UserAgent if not configured.  It is passed through to ElasticSearch::Client.

=back

=head1 USAGE

The L<Catalyst::Authentication::Store::ElasticSearch> storage module
is not called directly from application code.  You interface with it
through the $c->authenticate() call.

The L<Catalyst::Authentication::Store::ElasticSearch> fetches a user from ElasticSearch
by querying a view within a ElasticSearch design document.  The view is queried with
the C<username> passed in the authenticate call hash as the key, and returns
a ElasticSearch document.  This document is then passed to
L<Catalyst::Authentication::Store::ElasticSearch::User> to create the user object.

A suitable view map function is

        function(doc) {
            if (doc.username) {
                emit(doc.username, null);
            }
        }

=head1 METHODS

There are no publicly exported routines in the ElasticSearch authentication
store (or indeed in most authentication stores). However, below is a
description of the routines required by L<Catalyst::Plugin::Authentication>
for all authentication stores.  Please see the documentation for
L<Catalyst::Plugin::Authentication::Internals> for more information.

=head2 new ( $config, $app )

Constructs a new store object.

=head2 find_user ( $authinfo, $c )

Finds a user using the information provided in the $authinfo hashref and
returns the user, or undef on failure. This is usually called from the
Credential. This translates directly to a call to the User object's
load() method.

=head2 for_session ( $c, $user )

Prepares a user to be stored in the session.  This is delegated to
the User obect for_session method.

=head2 from_session ( $c, $frozenuser)

Revives a user from the session based on the info provided in $frozenuser.
This is delegated to the User object from_session method.

=head2 user_supports

Provides information about what the user object supports.

=head1 NOTES

This module is heavily based on L<Catalyst::Authentication::Store::DBIx::Class>.

The test scripts use clear text passwords. B<DO NOT DO THIS IN PRODUCTION.>
Use configuation as shown in the synopsis to use something stronger, such as
salted hash passwords.

The test scripts do not connect to a ElasticSearch instance as standard - they 
mock the responses that ElasticSearch would send.  To connect to a ElasticSearch instance,
set the C<CATALYST_COUCHDB_LIVE> environment variable before running the test suite.
The test suite assumes that a C<demouser> database exists, with a design document
called C<user> that contains a C<user> view, and that a document listing a test
user with username C<test> and password C<test> exists.  To configure this,
run the C<setup_database.pl> script in the C<t/script> directory on the distribution.
B<This script will remove any existing demouser database.>

=head1 BUGS AND LIMITATIONS

There are bound to be bugs - please email the author if you find any.

=head1 SEE ALSO

L<Catalyst::Authentication::Store::DBIx::Class>.
L<Catalyst::Plugin::Authentication>,
L<Catalyst::Plugin::Authentication::Internals>,
and L<Catalyst::Plugin::Authorization::Roles>

=head1 AUTHOR

Colin Bradford <cjbradford@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Colin Bradford.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

__END__
