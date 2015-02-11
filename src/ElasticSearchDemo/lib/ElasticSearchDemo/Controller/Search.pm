package ElasticSearchDemo::Controller::Search;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use Data::SearchEngine::ElasticSearch::Query;
use Data::SearchEngine::ElasticSearch;

=head1 NAME

ElasticSearchDemo::Controller::Search - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  #
  # TODO: 
  # - query check
  # - handle exceptions and errors from the Elasticsearch API
  #
  my $params = $c->req->params;

  my $page = $params->{page} || 1;
  $page = 1 if $page !~ /^\d+$/;
  my $entries_per_page = $params->{entries_per_page} || 2;

  my $config = ElasticSearchDemo->config()->{'Model::Search'};
  my ($index, $type) = ($config->{index}, $config->{type}{trackhub});
  my $fields = [ 'name', 'description', 'version' ];

  my $query = 
    Data::SearchEngine::ElasticSearch::Query->new(index     => $index,
  						  data_type => $type,
  						  page      => $page,
						  count     => $entries_per_page, 
  						  fields    => $fields,
  						  type      => 'match',
  						  query     => { _all => $params->{q} });
  my $se = Data::SearchEngine::ElasticSearch->new();
  my $results = $se->search($query);

  # my $search = $c->model('Search'); 
  # my $results = $search->search(index => $config->{index},
  # 				type  => $config->{type}{trackhub},
  # 				# http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/_finding_exact_values.html
  # 				# The term filter isn’t very useful on its own though. As discussed in Query DSL, the search API 
  # 				# expects a query, not a filter. To use our term filter, we need to wrap it with a filtered query:
  # 				# body  => { 
  # 				# query => {
  # 				# 	    "filtered" => { 
  # 				# 			   query => { "match_all" => {} }, # returns all documents (default, can omit)
  # 				# 			   filter => { term => { _all => $params->{'q'} } }
  # 				# 			   }
  # 				# 	    }
  # 				# },									       
  # 				body  => { fields    => [ 'name', 'description', 'version' ],
  # 					   query => { match => { _all => $params->{'q'} } } } # match query: full text search
  # 			       );

;
  $c->stash(columns         => $fields,
	    query_string    => $params->{q},
	    items           => $results->items,
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
