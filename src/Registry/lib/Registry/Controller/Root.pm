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

package Registry::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

use Try::Tiny;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Registry::Form::User::Help;

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=encoding utf-8

=head1 NAME

Registry::Controller::Root - Root Controller for Registry

=head1 DESCRIPTION

Provides functionality for login, help and some other defaults

=head1 METHODS

=head2 index

The root page (/)

=cut

sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  # Display the search form
  # $c->stash(template => 'search/search_form.tt');
  $c->stash(template => 'index.tt', bootstrap => 1);
}

=head2 default

Standard 404 error page

=cut

sub default :Path {
  my ( $self, $c ) = @_;
  $c->response->body( 'Page not found' );
  $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head2 learn_more

The page linked by the "Learn More" button in the front page

=cut 

sub learn_more :Path('/about') {
  my ($self, $c) = @_;
}

=head2 help

The help page with the contact form

=cut 

sub help :Path('/help') {
  my ($self, $c) = @_;

  my $help_form = Registry::Form::User::Help->new();

  $c->stash(template => "help.tt",
            form     => $help_form);

  return unless $help_form->process( params => $c->req->parameters );

  my ($name, $subject, $email, $message) =
    (
     $help_form->value->{name},
     $help_form->value->{subject},
     $help_form->value->{email},
     $help_form->value->{message}
    );
  my $email_message = 
    Email::MIME->create(header_str => 
                          [
                           From => $email,
                           To   => "trackhub-registry\@ebi.ac.uk",
                           Subject => $subject
                          ],
                          attributes =>
                          {
                           encoding => 'quoted-printable',
                           charset  => 'ISO-8859-1',
                          },
                          body_str => $message,
                               );
  try {
    sendmail($email_message);
  } catch {
    $c->stash(error_msg => "An unexpected error happened, couldn't send message to HelpDesk.<br/>Please contact it directly at helpdesk\@trackhubregistry.org using your email client.")
  };

  $c->stash(status_msg => sprintf "%sYour message has been sent to our HelpDesk.<br/>We'll contact you as soon as possible.", $name?"Thanks $name for contacting us. ":"");
}

=head2 submit

The page linked by the "How to Submit" button in the front page

=cut 

sub submit :Path('/submit_trackhubs') {
  my ($self, $c) = @_;
}

=head2 stats_test

An action added just to support the development of the stats interface.

=cut

sub stats_test :Path('stats') {
  my ($sefl, $c) = @_;

  # $c->stash();
}

=head2 login

Follows Catalyst::Plugin::Authentication mode of operation

=cut

sub login :Path('/api/login') Args(0) {
  my ($self, $c) = @_;

  my $is_readonly = 0;
  $is_readonly = Registry->config()->{'read_only_mode'};

  # Server is running on read only mode
  if($is_readonly){
    $c->stash(template => 'read_only_mode.tt');
    return;
  }

  $c->authenticate({}, 'http');

  # user should exist
  $c->user->auth_key(String::Random::random_string('s' x 64));

  $c->stash()->{auth_token} = $c->user->get('auth_key');
  $c->forward($c->view('JSON'));
}

__PACKAGE__->meta->make_immutable;

1;
