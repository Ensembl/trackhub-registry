=head1 LICENSE

Copyright [2015-2017] EMBL-European Bioinformatics Institute

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

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Controller::Login - A controller to manage login for authenticated users.

=head1 DESCRIPTION

This controller inherits from CatalystX::SimpleLogin::Controller::Login to override
the post login action so that after login users are immediately redirected to the page 
listing the trackhub they have submitted.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

package Registry::Controller::Login;
use Moose;

use namespace::autoclean;

BEGIN { extends 'CatalystX::SimpleLogin::Controller::Login' }

=head1 METHODS

=head2 do_post_login_redirect

Redirected an authenticated user to the page with the list of its trackhubs.

=cut

sub do_post_login_redirect {
  my ($self, $ctx) = @_;
  $ctx->res->redirect($ctx->uri_for($ctx->controller('User')->action_for('list_trackhubs'), [$ctx->user->username]));
}
 
1;
