package ElasticSearchDemo::Controller::Search;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

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

  my $index = 'test';
  my $type = 'trackhub';
  
  my $params = $c->req->params;
  my $query = $params->{'q'};

  #
  # Query check
  #

  my $search = $c->model('ElasticSearch');
  my $results = $search->search(index => $index,
				type  => $type,
				# body  => { query => { term => { alignment_software => $params->{'q'} } } }, # term filter: exact value
				# http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/_finding_exact_values.html
				# The term filter isn’t very useful on its own though. As discussed in Query DSL, the search API 
				# expects a query, not a filter. To use our term filter, we need to wrap it with a filtered query:
				# body  => { 
				# query => {
				# 	    "filtered" => { 
				# 			   query => { "match_all" => {} }, # returns all documents (default, can omit)
				# 			   filter => { term => { _all => $params->{'q'} } }
				# 			   }
				# 	    }
				# },									       
				body  => { query => { match => { _all => $params->{'q'} } } } # match query: full text search
			       );

  $c->stash(index => $index);
  $c->stash(type => $type);
  $c->stash(results => $results);
  $c->stash(template => 'search/results.tt');

    
}



=encoding utf8

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
