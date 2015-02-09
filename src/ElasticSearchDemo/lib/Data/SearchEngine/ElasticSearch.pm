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
    isa => 'Search::Elasticsearch',
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


no Moose;
__PACKAGE__->meta->make_immutable;


