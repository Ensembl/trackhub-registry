=head1 LICENSE

Copyright [2015-2019] EMBL-European Bioinformatics Institute

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

Registry::Utils::Exception - A throwable error class for non-Catalyst components

=head1 SYNOPSIS

try {
  Registry::Utils::Exception->throw('I broke');
} catch {
  print $_->message;
};

=head1 DESCRIPTION

An exception class, so we can generate errors that aren't stack traces when they make it to the user.

=cut

package Registry::Utils::Exception;

use Moose;
extends 'Throwable::Error';