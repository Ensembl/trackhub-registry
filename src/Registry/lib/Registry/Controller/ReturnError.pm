=head1 LICENSE

Copyright [2015-2023] EMBL-European Bioinformatics Institute

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

Registry::Controller::ReturnError - A controller to manage the display of errors.

=head1 DESCRIPTION

This is a controller whose actions are invoked by other controllers in case
some error occurs. It has actions to return bad request/no content codes
with customised messages.

=cut

package Registry::Controller::ReturnError;
use Moose;
use namespace::autoclean;
use Carp::Clan qw(^Registry::Controller::);
BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    'default'   => 'application/json',
#     'stash_key' => 'rest',
    'map'       => {
        'text/x-yaml'       => 'YAML::XS',
        'application/json'  => 'JSON::XS',
        'text/plain'        => 'JSON::XS',
        'text/html'         => 'YAML::HTML',
    }
);

=head1 METHODS

=head2 index

Main action to return a bad request status code with a message
extracted from the stack trace, if available. It otherwise emits
a default generic message.

=cut

sub index : Path : Args(0) : ActionClass('REST') {
    my ( $self, $c, $raw_error ) = @_;

    $c->log->error($raw_error);


    #     #     $error =~ s/\n/\\x/g;
    #     $error = "thist!";
    #     $error =~ s/s/\n/g;
    #     $c->log->warn( 'ERROR: ', $error );
    # my $raw_msg = $c->stash->{error};
    my ($error_cleaned) = $raw_error =~ m/MSG:\s(.*?)STACK/s;
    $error_cleaned ||= 'something bad has happened';
    $error_cleaned =~ s/\n//g;
    $self->status_bad_request( $c, message => $error_cleaned );
}

=head2 index_GET

Not implemented

=cut

sub index_GET { }

=head2 index_POST

Not implemented

=cut

sub index_POST { }

=head2 custom

Action to return bad request status code with a customised error message.

=cut

sub custom : Path : Args(0) : ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $c->log->error($error_msg);
    
  $self->status_bad_request( $c, message => $error_msg );
}

=head2 custom_GET

Not implemented

=cut

sub custom_GET { }

=head2 custom_POST

Not implemented

=cut

sub custom_POST { }

=head2 custom_PUT

Not implemented

=cut

sub custom_PUT { }

=head2 no_content

Action to return a no content status code with a customised error message

=cut

sub no_content: Path : Args(0) : ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $c->log->error($error_msg);
  $self->status_no_content( $c, message => $error_msg );
}

=head2 no_content_GET

Not implemented

=cut

sub no_content_GET { }

=head2 no_content_POST

Not implemented

=cut

sub no_content_POST { }

=head2 not_found

Action to return a Not Found status with a customised error message

=cut

sub not_found: Path : Args(0) : ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $self->status_not_found($c, message => $error_msg);
}

=head2 not_found_GET

Not implemented

=cut

sub not_found_GET { }

=head2 not_found_POST

Not implemented

=cut

sub not_found_POST { }

__PACKAGE__->meta->make_immutable;

1;
