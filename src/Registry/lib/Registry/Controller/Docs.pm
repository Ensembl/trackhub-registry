package Registry::Controller::Docs;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

Registry::Controller::Docs - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

###############
# Search Docs #
###############

sub search :Local { }

sub results_page :Path('/docs/search/results') { }

sub advanced_search :Path('/docs/search/advanced') { }

######################
# TH Management Docs #
######################

sub th_management_overview :Path('/docs/management/overview') { }

sub th_management_submission :Path('/docs/management/submission') { }

sub th_management_dashboard :Path('/docs/management/dashboard') { }

sub registration :Local { }

sub management :Local { }

sub dashboard :Local { }

#####################
# Registry API Docs #
#####################

sub apis :Local { }

sub th_modelling :Path('/docs/api/modelling') { }

sub api_info :Path('/docs/api/info') { }

sub api_registration :Path('/docs/api/registration') { }

sub api_registration_workflow_login :Path('/docs/api/registration/workflow/login') { }

sub api_registration_workflow_thregister :Path('/docs/api/registration/workflow/thregister') { }

sub api_registration_workflow_thlist :Path('/docs/api/registration/workflow/thlist') { }

sub api_registration_workflow_thupdate :Path('/docs/api/registration/workflow/thupdate') { }

sub api_registration_workflow_thdelete :Path('/docs/api/registration/workflow/thdelete') { }

sub api_registration_workflow_logout :Path('/docs/api/registration/workflow/logout') { }

sub api_registration_reference :Path('/docs/api/registration/reference') { }

sub api_search :Path('/docs/api/search') { }

#############
# Misc docs #
#############

sub assembly_support :Local { }

=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
