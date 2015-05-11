package Data::SearchEngine::ElasticSearch;

use Moose;

#
# ABSTRACT: Search::Elasticsearch support for Data::SearchEngine
# Adapt Data::SearchEngine::ElasticSearch to work
# with the new Search::ElasticSearch, since the original module relies
# on the deprecated ElasticSearch module
#

 
use Clone qw(clone);
use Time::HiRes;
use Try::Tiny;
use Search::Elasticsearch;
 
with (
    'Data::SearchEngine',
    'Data::SearchEngine::Modifiable'
);
 
use Data::SearchEngine::Item;
use Data::SearchEngine::Paginator;
use Data::SearchEngine::ElasticSearch::Results;


has '_es' => (
    is => 'ro',
    isa => 'Search::Elasticsearch::Client::Direct',
    lazy => 1,
    default => sub {
        my $self = shift;
        return Search::Elasticsearch->new(
            nodes     => $self->nodes,
            transport => $self->transport
        )
    }
);
 
has 'nodes' => (
    is => 'ro',
    isa => 'Str|ArrayRef',
    default => '127.0.0.1:9200'
);
 
has 'transport' => (
    is => 'ro',
    isa => 'Str',
    default => '+Search::Elasticsearch::Transport'
);

#
# Data::SearchEngine|Data::SearchEngine::Modifiable' requires the methods 
# 'add', 'present', 'remove', 'remove_by_id', and 'update'
#
# this is to update, change according to new interface , e.g. bulk_index not supported
sub add {
  my ($self, $items, $options) = @_;
 
  my @docs;
  foreach my $item (@{ $items }) {
 
    my %data = %{ $item->values };
 
    my %doc = (
	       index => delete($data{index}),
	       type => delete($data{type}),
	       id => $item->id,
	       data => \%data
	      );
    # Check for a version
    if (exists($data{'_version'})) {
      $doc{version} = delete($data{'_version'});
    }
    push(@docs, \%doc);
  }
  $self->_es->bulk_index(\@docs);
}
 
 
 
sub present {
  my ($self, $item) = @_;
 
  my $data = $item->values;
 
  try {
    my $result = $self->_es->get(
				 index => delete($data->{index}),
				 type => delete($data->{type}),
				 id => $item->id
				);
  } catch {
    # ElasticSearch throws an exception if the document isn't there.
    return 0;
  }
 
    return 1;
}
 
sub remove {
  die("not implemented");
}
 
 
sub remove_by_id {
  my ($self, $item) = @_;
 
  my $data = $item->values;
 
  $self->_es->delete(
		     index => $data->{index},
		     type => $data->{type},
		     id => $item->id
		    );
}
 
sub update {
  my $self = shift;
 
  $self->add(@_);
}
 
sub search {
  my ($self, $query, $filter_combine) = @_;
 
  unless(defined($filter_combine)) {
    $filter_combine = 'and';
  }
 
  # the options hash contains a set of parameters allowed
  # in the request body
  # see http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-request-body.html
  my $options;

  # see http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/query-dsl-queries.html
  # for a list of possible queries
  if ($query->has_query) {
    die "Queries must have a type." unless $query->has_type;
    $options->{body}{query} = { $query->type => $query->query };
  }
 
  $options->{index} = $query->index;
  # restrict the search to a particular data type
  # Class Data::SearchEngine::ElasticSearch::Query
  # has been introduced to support specifying data type
  # in the query.
  # The new Query inherits from Data::SearchEngine::Query
  $options->{type} = $query->data_type
    if $query->has_datatype;

  if ($query->has_debug) {
    # Turn on explain
    $options->{explain} = 1;
  }
 
  # this has to be reviewed, since the search API expects a query
  # not a filter. Filters need to be wrapped in a filtered query
  # http://distinctplace.com/2014/07/29/build-zappos-like-products-facets-with-elasticsearch/
  # shows an example where the following applies
  my @facet_cache = ();
  if ($query->has_filters) {
    foreach my $filter ($query->filter_names) {
      push @facet_cache, { term => { $filter => $query->get_filter($filter) } };
    }
    $options->{body}{filter}{$filter_combine} = \@facet_cache;
  }
 
  # and this one too
  # See http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-facets.html
  # "Facets are deprecated and will be removed in a future release. You are encouraged to migrate 
  #  to aggregations instead"
  if ($query->has_facets) {
    # Copy filters used in the overall query into each facet, thereby
    # limiting the facets to only counting against the filtered bits.
    # This is really to replicate my expecations and the way facets are
    # usually used.
    my %facets = %{ $query->facets };
     
    if ($query->has_filters) {
      foreach my $f (keys %facets) {
  	$facets{$f}->{facet_filter}->{$filter_combine} = \@facet_cache;
      }
    }
 
    # Shlep the facets into the final query, even if we didn't do anything
    # with the filters above.
    $options->{body}{facets} = \%facets;
  }

  # support for aggregations
  if ($query->has_aggregations) {
    my %aggs = %{ $query->aggregations };
     
    if ($query->has_filters) {
      foreach my $f (keys %aggs) {
	# does logical AND/OR work with aggregations?
	# cannot find mentioned in the definitive guide
  	# $aggs{$f}->{filter}->{$filter_combine} = \@facet_cache;
	# $aggs{$f}->{filter} = { terms => { field => 'species.scientific_name' } };
	# $aggs{$f}->{filters}{filters} = \@facet_cache;
      }
    }
 
    # Shlep the facets into the final query, even if we didn't do anything
    # with the filters above.
    $options->{body}{aggs} = \%aggs;
  }

  if ($query->has_order) {
    $options->{sort} = $query->order;
  }
 
  if ($query->has_fields) {
    $options->{fields} = $query->fields;
  }
 
  $options->{from} = ($query->page - 1) * $query->count;
  $options->{size} = $query->count;
 
  my $start = Time::HiRes::time;
  my $resp = $self->_es->search($options);
 
  my $page = $query->page;
  my $count = $query->count;
  my $hit_count = $resp->{hits}->{total};
  my $max_page = $hit_count / $count;
  if ($max_page != int($max_page)) {
    # If trying to calculate how many pages we _could_ have gives us a
    # non integer, add one to the page after inting it so we get the right
    # integer.
    $max_page = int($max_page) + 1;
  }
  if ($page > $max_page) {
    $page = $max_page;
  }
 
  my $pager = Data::SearchEngine::Paginator->new(
						 current_page => $page || 1,
						 entries_per_page => $count,
						 total_entries => $hit_count
						);
 
  my $result = Data::SearchEngine::ElasticSearch::Results->new(
							       query => $query,
							       pager => $pager,
							       elapsed => time - $start,
							       raw => $resp
							      );
 
  if (exists($resp->{facets})) {
    foreach my $facet (keys %{ $resp->{facets} }) {
      my $href = $resp->{facets}->{$facet};
      if (exists($href->{terms})) {
	my @vals = ();
	foreach my $term (@{ $href->{terms} }) {
	  push(@vals, { count => $term->{count}, value => $term->{term} });
	}
	$result->set_facet($facet, \@vals);
      }
    }
  }
  if (exists($resp->{aggregations})) {
    my $buckets = [];
    $self->_get_buckets($resp->{aggregations}, $buckets);
    # use Data::Dumper; 
    # print Dumper $resp->{aggregations};
    # print Dumper $buckets;
    $result->{aggregations} = $buckets;
  }

  foreach my $doc (@{ $resp->{hits}->{hits} }) {
    my $values = $doc->{_source};
    $values->{_index} = $doc->{_index};
    $values->{_version} = $doc->{_version};
    $result->add($self->_doc_to_item($doc));
  }
 
  return $result;
}

sub _get_buckets {
  my ($self, $hash, $buckets) = @_;
  foreach my $key (keys %{$hash}) {
    next if $key eq 'doc_count';
    if ($key eq 'buckets') {
      foreach my $agg (@{$hash->{$key}}) {
	push @{$buckets}, { count => $agg->{doc_count}, value => $agg->{key} }
      }
      return;
    }

    $self->_get_buckets($hash->{$key}, $buckets) if ref $hash->{$key} eq 'HASH';
  }
}


sub _doc_to_item {
  my ($self, $doc) = @_;
 
  # If fields are specified as a parameter of the search body,
  # ES returns each field wrapped in an arrayref. 
  # A way to prevent this is to specify a fielddata_fields param,
  # as indicated in the ES documentation, see
  # http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-search.html
  # Unfortunately, either ES or Search::Elasticsearch does complain
  # in case fielddata_fields is specified.
  # In this case, loop over each field returned and grab the
  # first element of the corresponding arrayref
  
  # my $values = $doc->{_source} || $doc->{fields};
  my $values;
  if ($doc->{_source}) {
    $values = $doc->{_source};
  } else {
    die "fields should have been specified"
      unless $doc->{fields};
    foreach my $field (keys %{$doc->{fields}}) {
      $values->{$field} = $doc->{fields}{$field};
      $values->{$field} = $doc->{fields}{$field}[0]
	if ref($doc->{fields}{$field}) =~ /ARRAY/;
    }
  }

  $values->{_index} = $doc->{_index};
  $values->{_version} = $doc->{_version};
  return Data::SearchEngine::Item->new(
				       id      => $doc->{_id},
				       score   => $doc->{_score} || 0,
				       values  => $values,
				      );
}
 
sub find_by_id {
  my ($self, $index, $type, $id) = @_;
 
  my $doc = $self->_es->get(
			    index => $index,
			    type => $type,
			    id => $id
			   );
 
  return $self->_doc_to_item($doc);
}

no Moose;
__PACKAGE__->meta->make_immutable;


