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


sub search :Local { }

sub results_page :Path('/docs/search/results') { }

sub advanced_search :Path('/docs/search/advanced') { }

sub registration :Local { }

sub management :Local { }

sub dashboard :Local { }

sub apis :Local { }

sub th_modelling :Path('/docs/api/modelling') { }

sub registration_api :Path('/docs/api/registration') { }

sub search_api :Path('/docs/api/search') { }


=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
