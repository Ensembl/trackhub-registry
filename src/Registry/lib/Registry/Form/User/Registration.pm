=head1 LICENSE

Copyright [2015-2020] EMBL-European Bioinformatics Institute

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

Registry::Form::User::Registration - Form for user registration

=head1 DESCRIPTION

Implements a form capturing the information submitted by the users who wants
to register themselves with the service and submit trackhubs.

=cut

package Registry::Form::User::Registration;
use Moose;
use HTML::FormHandler::Moose;
use namespace::autoclean;

extends 'Registry::Form::User::Profile';

has '+name' => ( default => 'registration_form' );

has_field 'username' => (
    label            => 'Username',
    type             => 'Text',
    required         => 1,
    required_message => 'Please enter your username.',
);

has_field 'gdpr_accept' => (
    label            => 'gdpr_accept',
    type             => 'Checkbox',
    input_without_param => 0,
    checkbox_value   => 1
);

__PACKAGE__->meta->make_immutable;

1;
