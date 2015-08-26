package Registry::Controller::API::Search;
use Moose;
use namespace::autoclean;

use JSON;
use Try::Tiny;

use Data::SearchEngine::ElasticSearch::Query;
use Data::SearchEngine::ElasticSearch;

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
		    'default'   => 'application/json',
		    # map => {
		    # 	    'text/plain' => ['YAML'],
		    # 	   }
		   );

=head1 NAME

Registry::Controller::Search::API - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 search

=cut

sub search :Path('/api/search') Args(0) ActionClass('REST') {
  my ( $self, $c ) = @_;

  my $params = $c->req->params;
  my $page = $params->{page} || 1;
  $page = 1 if $page !~ /^\d+$/;
  my $entries_per_page = $params->{entries_per_page} || 5;

  $c->stash( page => $page, entries_per_page => $entries_per_page );
}

sub search_POST {
  my ($self, $c) = @_;

  return $self->status_bad_request($c, message => "Missing data")
    unless defined $c->req->data;

  my $params = $c->req->params;
  my $data = $c->req->data;

  my ($query_type, $query_body) = ('match_all', {});
  my $query = $data->{query};
  
  if ($query) {
    # $query_type = 'match';
    # $query_body = { _all => $query };
    $query_type = 'query_string';
    $query_body = { query => $query }; # default field is _all
  }

  my $config = Registry->config()->{'Model::Search'};
  my ($index, $type) = ($config->{index}, $config->{type}{trackhub});

  my $query_args = 
    {
     index     => $index,
     data_type => $type,
     page      => $c->stash->{page},
     count     => $c->stash->{entries_per_page}, 
     type      => $query_type,
     query     => $query_body,
    };

  # process filters, i.e. species, assembly, hub
  my $filters;
  $filters->{'species.scientific_name'} = $data->{species}
    if $data->{species};
  $filters->{'assembly.name'} = $data->{assembly}
    if $data->{assembly};
  $filters->{'hub.name'} = $data->{hub}
    if $data->{hub};
  $query_args->{filters} = $filters if $filters;

  # do the search
  my $results;
  my $se = Data::SearchEngine::ElasticSearch->new();
  
  try {
    $results = $se->search(Data::SearchEngine::ElasticSearch::Query->new($query_args));
  } catch {
    $c->go('ReturnError', 'custom', [qq{$_}]);
  };

  # build the JSON response
  my $response = { total_entries => $results->pager->total_entries };

  # On recent installations, we cannot simply assign the response items to the array 
  # of Data::SearchEngine::Item search results.
  # Catalyst::Action::Serialize::JSON complains it cannot deal with blessed references.
  # Build the response items as an array of simple hash references.
  foreach my $item (@{$results->items}) {
    my $response_item = $item->{values};

    # strip away the metadata/configuration field from each search result
    # this will save bandwidth
    # when a trackdb is chosen the client will request all the details by id
    # remove also other fields the user is not interested in
    map { delete $response_item->{$_} } qw ( source _index owner _version created data configuration );

    $response_item->{id} = $item->{id};
    $response_item->{score} = $item->{score};

    push @{$response->{items}}, $response_item;
  }
  $response->{items} = [] unless scalar @{$results->items};

  # strip away the metadata/configuration field from each search result
  # this will save bandwidth
  # when a trackdb is chosen the client will request all the details by id
  # map { delete $_->{values}{data}; delete $_->{values}{configuration} } @{$response->{items}};

  $self->status_ok($c, entity => $response);
}

=head2 trackdb

/api/search/trackdb/:id - return a trackDB document by ID

=cut 

sub trackdb :Local Args(1) ActionClass('REST') {
  my ($self, $c, $doc_id) = @_;

  # if the doc with that ID doesn't exist, ES throws exception
  # intercept but do nothing, as the GET method will handle
  # the situation in a REST appropriate way.
  eval { $c->stash(trackdb => $c->model('Search')->get_trackhub_by_id($doc_id)); };
}

=head2 trackdb_GET

Return trackhub document content for a document
with the specified ID

=cut

sub trackdb_GET {
  my ($self, $c, $doc_id) = @_;

  my $trackdb = $c->stash()->{trackdb};
  if ($trackdb) {
    # strip away the metadata field
    delete $trackdb->{data};

    $self->status_ok($c, entity => $trackdb);
  } else {
    $self->status_not_found($c, message => "Could not find trackdb doc (ID: $doc_id)");    
  }
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
