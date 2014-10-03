package ElasticSearchDemo::Indexer;

use strict;
use warnings;

#
# TODO
# Have to use this until I implement with Moose
#
BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/..";
}

use Carp;
use LWP;
use JSON;

use ElasticSearchDemo::Utils;
use ElasticSearchDemo::Model::ElasticSearch;

sub new {
  my ($caller, $dir, $index, $type, $mapping) = @_;
  defined $dir or croak "Undefined directory arg";
  defined $index and defined $type or
    croak "Undefined index|type parameters";

  my $class = ref($caller) || $caller;
  my $self = bless({ index => $index, type => $type, mapping => "$dir/$mapping" }, $class);

  #
  # add example trackhub documents
  #
  # NOTE
  # Adding version [1-2].1 as in original [1-2]
  # search doesn't work as it's not indexing
  # the fields
  #
  my @doclist = ('bluprint1.1.json', 'bluprint2.1.json');
  my $id = 1;
  foreach my $doc (@doclist) {
    my $doc_path = "$dir/$doc";
    -e $doc_path or croak "File $doc_path does not exist";
    $self->{docs}{$id++} = $doc_path;
  }

  &ElasticSearchDemo::Utils::es_running() or
    croak "ElasticSearch instance not available";

  $self->{es} = ElasticSearchDemo::Model::ElasticSearch->new();

  return $self;
}

sub index {
  my $self = shift;

  my ($index, $type) = ($self->{index}, $self->{type});
  my $indices = $self->{es}->indices;

  #
  # create the index 
  #
  # delete the index if it exists
  $indices->delete(index => $index) and carp "Deleting index $index"
    if $indices->exists(index => $index);
    
  # recreate the index
  carp "Creating index $index";
  $indices->create(index => $index); 
  
  #
  # create the mapping (trackhub)
  #
  my $mapping_json = from_json(&ElasticSearchDemo::Utils::slurp_file($self->{mapping}));
  $indices->put_mapping(index => $index,
			type  => $type,
			body  => $mapping_json);
  $mapping_json = $indices->get_mapping(index => $index,
					type  => $type);
  exists $mapping_json->{$index}{mappings}{$type} and carp "Mapping created";

  #
  # add example trackhub documents
  #
  foreach my $id (keys %{$self->{docs}}) {
    carp "Indexing document $self->{docs}{$id}";
    $self->{es}->index(index   => $index,
		       type    => $type,
		       id      => $id,
		       body    => from_json(&slurp_file($self->{docs}{$id})));
  }

  # The refresh() method refreshes the specified indices (or all indices), 
  # allowing recent changes to become visible to search. 
  # This process normally happens automatically once every second by default.
  carp "Flushing recent changes";
  $indices->refresh(index => $index);
}

1;
