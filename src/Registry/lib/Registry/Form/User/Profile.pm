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

=head1 NAME

Registry::Form::User::Registration - Form for user profile

=head1 DESCRIPTION

This represents the data of the form presented to the user who wants to update
his/her profile.

=cut

package Registry::Form::User::Profile;
use Moose;
use HTML::FormHandler::Moose;
use namespace::autoclean;
extends 'HTML::FormHandler';

has '+name' => ( default => 'profile_form' );

has_field 'first_name' => (
    label            => 'First name',
    type             => 'Text',
);
 
has_field 'last_name' => (
    label            => 'Last name',
    type             => 'Text',
);
 
has_field 'affiliation' => (
    label            => 'Affiliation',
    type             => 'Text',
);

has_field 'email' => (
    label            => 'Email',
    type             => 'Email',
    required         => 1,
    required_message => 'Please enter the contact email.',
);

has_field 'password' => (
    label            => 'Password',
    type             => 'Password',
    required         => 1,
    required_message => 'Please enter your password.',
    minlength        => 5
);

has_field 'password_conf' => (
    label            => 'Password (again)',
    type             => 'Password',
    required         => 1,
    required_message => 'Confirm your password.',
    minlength        => 5
);

has_field 'check_interval' => (
    type             => 'Select',
    options          => [{ value => 0, label => 'Automatic'}, { value => 1, label => 'Weekly'}, { value => 2, label => 'Monthly'} ]
);

has_field 'continuous_alert' => (
    label            => 'Receive continuous alerts',
    type             => 'Checkbox',
    input_without_param => 0,
    checkbox_value   => 1
);

has_field 'submit'  => (
    type => 'Submit',
    value => 'Update',
    element_class => ['btn']
);

=head1 METHODS

=head2 validate

Executed after the user presses submit, checks whether password and password confirmation fields match.

=cut

sub validate {
    my $self = shift;

    if ($self->field('password_conf')->value ne $self->field('password')->value ) {
        $self->field('password_conf')->add_error('Passwords do not match. Please try again.');
    }
};

__PACKAGE__->meta->make_immutable;

1;
