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

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Controller::Docs - Catalyst Controller

=head1 DESCRIPTION

Provide actions for assembling the pages corresponding to the URLs of the documentation.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

package Registry::Controller::Docs;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 METHODS

cut

###############
# Search Docs #
###############

=head2 search

Action for docs/search URL (the main search documentation page)

=cut

sub search :Local { }

=head2 results_page

Action for the docs/search/results URL (the search results page)

=cut

sub results_page :Path('/docs/search/results') { }

=head2 advanced_search

Action for the /docs/search/advanced URL (the advanced search page)

=cut

sub advanced_search :Path('/docs/search/advanced') { }

######################
# TH Management Docs #
######################

=head2 th_management_overview

Action for /docs/management/overview URL

=cut

sub th_management_overview :Path('/docs/management/overview') { }

=head2 th_management_modelling

Action for /docs/management/modelling URL

=cut

sub th_management_modelling :Path('/docs/management/modelling') { }

=head2 th_management_assembly_support

Action for the /docs/management/assembly_support URL

=cut

sub th_management_assembly_support :Path('/docs/management/assembly_support') { }

=head2 th_management_dashboard

Action for the /docs/management/dashboard URL

=cut

sub th_management_dashboard :Path('/docs/management/dashboard') { }

#####################
# Registry API Docs #
#####################

=head2 apis

Action for the /docs/apis URL

=cut

sub apis :Local { }

=head2 th_modelling

Action for the /docs/api/modelling URL

=cut

sub th_modelling :Path('/docs/api/modelling') { }

=head2 api_info

Action for the /docs/api/info URL

=cut

sub api_info :Path('/docs/api/info') { }

=head2 api_registration

Action for the /docs/api/registration URL

=cut

sub api_registration :Path('/docs/api/registration') { }

=head2 api_registration_workflow_login

Action for the /docs/api/registration/workflow/login URL

=cut

sub api_registration_workflow_login :Path('/docs/api/registration/workflow/login') { }

=head2 api_registration_workflow_thregister

Action for the /docs/api/registration/workflow/thregister URL

=cut

sub api_registration_workflow_thregister :Path('/docs/api/registration/workflow/thregister') { }

=head2 api_registration_workflow_thlist

Action for the /docs/api/registration/workflow/thlist URL

=cut

sub api_registration_workflow_thlist :Path('/docs/api/registration/workflow/thlist') { }

=head2 api_registration_workflow_thupdate

Action for the /docs/api/registration/workflow/thupdate URL

=cut

sub api_registration_workflow_thupdate :Path('/docs/api/registration/workflow/thupdate') { }

=head2 api_registration_workflow_thdelete

Action for the /docs/api/registration/workflow/thdelete URL

=cut

sub api_registration_workflow_thdelete :Path('/docs/api/registration/workflow/thdelete') { }

=head2 api_registration_workflow_logout

Action for the /docs/api/registration/workflow/logout URL

=cut

sub api_registration_workflow_logout :Path('/docs/api/registration/workflow/logout') { }

=head2 api_registration_reference

Action for the /docs/api/registration/reference URL

=cut

sub api_registration_reference :Path('/docs/api/registration/reference') { }

=head2 api_search

Action for the /docs/api/search URL

=cut

sub api_search :Path('/docs/api/search') { }

#############
# Misc docs #
#############

__PACKAGE__->meta->make_immutable;

1;
