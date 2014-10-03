package ElasticSearchDemo::Indexer;

use strict;
use warnings;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/..";
}

use Carp;
use LWP;
use ElasticSearchDemo::Model::ElasticSearch;

sub new {
  my ($caller, $dir, $index, $type) = @_;
  defined $dir or croak "Undefined directory arg";
  defined $index and defined $type or
    croak "Undefined index|type parameters";

  my $class = ref($caller) || $caller;
  my $self = bless({ index => $index, type => $type }, $class);

  my @doclist = ('bluprint1.1.json', 'bluprint2.1.json');
  my $id = 1;
  foreach my $doc (@doclist) {
    my $doc_path = "$dir/$doc";
    -e $doc_path or croak "File $doc_path does not exist";
    $self->{docs}{$id++} = $doc_path;
  }

  $self->_es_running() or
    croak "ElasticSearch instance not available";

  $self->{es} = ElasticSearchDemo::Model::ElasticSearch->new();

  return $self;
}

sub index {
  my $self = shift;

  my ($index, $type) = ($self->{index}, $self->{type});
  my $indices = $self->{es}->indices;
  
}

sub _es_running {
  my $self = shift;

  return get('http://localhost:9200')->is_success;
}
