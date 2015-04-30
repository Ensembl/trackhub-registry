package Registry::Controller::Search;
use Moose;
use namespace::autoclean;

use Try::Tiny;
use Catalyst::Exception;
use Data::SearchEngine::ElasticSearch::Query;
use Data::SearchEngine::ElasticSearch;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

Registry::Controller::Search - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

#
# TODO: 
# - Data::SearchEngine::ElasticSearch instance must be initialised
#   with location of nodes from config file
#
sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  my $params = $c->req->params;

  # Basic query check: if empty query params, matches all document
  my ($query_type, $query_body) = ('match_all', {});
  if ($params->{q}) {
    $query_type = 'match';
    $query_body = { _all => $params->{q} };
  } 

  my $page = $params->{page} || 1;
  $page = 1 if $page !~ /^\d+$/;
  my $entries_per_page = $params->{entries_per_page} || 10;

  my $config = Registry->config()->{'Model::Search'};
  my ($index, $type) = ($config->{index}, $config->{type}{trackhub});
  my $fields = ['name', 'description', 'version'];

  my $query_args = 
    {
     index     => $index,
     data_type => $type,
     page      => $page,
     count     => $entries_per_page, 
     type      => $query_type,
     query     => $query_body,
     facets    => { species  => { terms => { field => 'species.tax_id' } },
		    assembly => { terms => { field => 'assembly.name' } } }
    };

  # pass extra (i.e. besides query) parameters as ANDed filters
  my $filters;
  foreach my $param (keys %{$params}) {
    next if $param eq 'q' or $param eq 'page';
    my $filter = ($param =~ /species/)?'species.tax_id':'assembly.name';
    $filters->{$filter} = $params->{$param};
  }
  $query_args->{filters} = $filters if $filters;

  my $query = 
    Data::SearchEngine::ElasticSearch::Query->new($query_args);
  my $se = Data::SearchEngine::ElasticSearch->new();
  my $results;

  # do the search
  try {
    $results = $se->search($query);
  } catch {
    Catalyst::Exception->throw( qq/$_/ );
  };

  # TODO: process facets in order to show more meaningful values, 
  # e.g. Species name instead of tax id
  my $facets = $results->facets;

  $c->stash(# columns         => $fields,
	    query_string    => $params->{q},
	    filters         => $params,
	    items           => $results->items,
	    facets          => $facets,
	    pager           => $results->pager,
	    template        => 'search/results.tt');
    
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
