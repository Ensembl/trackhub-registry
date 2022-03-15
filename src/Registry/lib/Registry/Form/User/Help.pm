=head1 LICENSE

Copyright [2015-2022] EMBL-European Bioinformatics Institute

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

package Registry::Form::User::Help;
use Moose;
use HTML::FormHandler::Moose;
use namespace::autoclean;
extends 'HTML::FormHandler';

has '+name' => (
    default => 'help_form'
);

has_field name => (
    label            => 'Your name:',
    type             => 'Text',
);

has_field email => (
    label            => 'Your email:',
    type             => 'Email',
    required         => 1,
    required_message => 'Please enter the contact email.',
);

has_field subject => (
    label            => 'Subject:',
    type             => 'Text',
);

has_field message => (
    label            => 'Message:',
    type             => 'TextArea',
);

has_field phone => (
    label            => 'Phone:',
    type             => 'Text',
    tabindex         => '-1',
    autocomplete     => 'off',
    style            => 'display:none !important',
);

has_field submit  => (
    type => 'Submit',
    value => 'Send',
    element_class => ['btn']
);

__PACKAGE__->meta->make_immutable;

1;
