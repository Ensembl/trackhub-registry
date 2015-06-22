package Registry::Controller::SearchAPI;
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

Registry::Controller::SearchAPI - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub search :Path('/api/search') :Args(0) ActionClass('REST') {
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
  use Data::Dumper; $c->log->debug(Dumper $data);

  my ($query_type, $query_body) = ('match_all', {});
  my $query = $data->{query};
  
  if ($query) {
    $query_type = 'match';
    $query_body = { _all => $params->{q} };
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
  my $response = { total_entries => $results->pager->total_entries, items => $results->items };
  
  # strip away the metadata field from each search result
  my $items => $results->items;
  map { delete $_->{values}{data} } @{$response->{items}};

  $self->status_ok($c, entity => $response);
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
