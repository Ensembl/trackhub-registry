=head1 LICENSE

Copyright [2015-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Catalyst::Model::ElasticSearch;

use Moose;
use namespace::autoclean;
use Search::Elasticsearch;
use Registry::Utils::File qw/slurp_file/;
use Carp;
use JSON;
extends 'Catalyst::Model';


=head1 SYNOPSIS
  
  package My::App::Model::Search;
  use Moose;
  use namespace::autoclean;
  extends 'Catalyst::Model::Search::ElasticSearch';

  __PACKAGE__->meta->make_immutable;
  1;

=head1 DESCRIPTION

Adapted from Catalyst::Model::Search::ElasticSearch

This base Catalyst::Model is inherited by any models that need to access Elasticsearch
It provides convenient access to the ES REST API, and auto-populates it with schema as
necessary.


=head1 CONFIGURATION PARAMETERS AND ATTRIBUTES

=head2 nodes

A list of nodes to connect the Elasticsearch client to.

=cut

has 'nodes' => (
  is      => 'rw',
  lazy    => 1,
  default => "localhost:9200",
);

=head2 transport

The transport to use to interact with the Elasticsearch API.  See L<Search::Elasticsearch::Transport|Search::Elasticsearch::Transport> for options.
Rarely needed to be overriden

=cut

has 'transport' => (
  is      => 'rw',
  lazy    => 1,
  default => "+Search::Elasticsearch::Transport",
);

=head2 _additional_opts

Stores other key/value pairs to pass to L<Search::Elasticsearch|Search::Elasticsearch>.

=cut

has '_additional_opts' => (
  is      => 'rw',
  lazy    => 1,
  isa     => 'HashRef',
  default => sub { { send_get_body_as => 'POST', cxn_pool => 'Static'} },
  # Here POST is used to deal with a restrictive firewall that strips body from GET messages
  # Elasticsearch is more progressive than firewall vendors
);

=head2 schema

We need to know both where our backend is, and what the indexes we are using are called
Takes the form:

schema => {
  $schema_type => {
    mapping_file => $path, # A JSON index mapping file for Elasticsearch
    index_name => $name, # A name for the index we are using
    type => $type # A type for the index, see ES documentation on index types
  }
}

One of the schema types is expected to be called 'trackhub'

=cut

has schema => (
  is => 'ro',
  isa => 'HashRef'
);


=head2 _es

The L<Search::Elasticsearch> object.

Most of the common methods you would call on this instance are proxied by handler methods:
$self->search() , $self->create() etc.
Otherwise, $self->_es->search()

Several helper methods have been replaced by the Search::Elasticsearch::Bulk
class. Similarly, scrolled_search() has been replaced by the Search::Elasticsearch::Scroll.
These helper classes are accessible as:
  $bulk   = $self->bulk_helper( %args_to_new );
  $scroll = $self->scroll_helper( %args_to_new );

Other methods return a Search::Elasticsearch::Client::Direct

See https://metacpan.org/pod/Search::Elasticsearch::Client::Direct for a list of methods
grouped according to category

=cut

has '_es' => (
  is       => 'ro',
  lazy     => 1,
  builder  => '_build_es',
  handles  => {
    map { $_ => $_ }
      qw(
      search scrolled_search count index get get_source mget create delete
      bulk bulk_helper scroll_helper indices
      )
  },
);

sub _build_es {
  my $self = shift;
  return Search::Elasticsearch->new(
    nodes     => $self->nodes,
    transport => $self->transport,
    %{ $self->_additional_opts },
  );
}

around BUILDARGS => sub {
  my $orig   = shift;
  my $class  = shift;

  my $params = $class->$orig(@_);

  if (defined $params->{servers}) {
    carp "Passing 'servers' is deprecated, use 'nodes' now";
    $params->{nodes} = delete $params->{servers};
  }
  my %additional_opts = %{$params};
  delete $additional_opts{$_} for qw/ nodes transport /;
  $params->{_additional_opts} = \%additional_opts;
  return $params;
};

# Automatically deploy schemas to the configured backend if it is required
around _build_es => sub {
  my $orig = shift;
  my $self = shift;
  
  my $client = $self->$orig(@_);

  unless (
    defined $self->schema
    && exists $self->schema->{trackhub}
  ) {
    croak 'Server config file for '.$self.' must have a section defining
      <schema>
        <trackhub>
          mapping_file $hub_mapping_json
          index_name   $es_hub_index_name
          type         trackdb
        </trackhub>
        <report>
          mapping_file $report_mapping_json
          index_name   $es_report_index_name
          type         report
        </report>
      </schema>'
  }

  while ( my ($schema_name, $config) = each %{ $self->schema } ) {
      
    my $schema_path = $config->{mapping_file};
    print "Creating index from config '$schema_name' with mapping $schema_path\n";
    
    # Create indexes and load mappings if they're not present
    unless ($client->indices->exists( index => $config->{index_name} ) ) {
      $client->indices->create(
        index => $config->{index_name},
        # type => $config->{type},
        body => decode_json( slurp_file( $schema_path ) )
      );
      $client->indices->refresh; # If only ES were a proper database
    }
  }
  return $client;
};


=head1 SEE ALSO

=over

=item *

The Catalyst Advent article on integrating Elasticsearch into your app: L<http://www.catalystframework.org/calendar/2010/2>

=item *

L<Search::Elasticsearch|Search::Elasticsearch> - Elasticsearch interface this
model provides access to

=item *

L<http://www.elasticsearch.org/> - Open Source Distributed Real Time Search and Analytics

=back

=cut


__PACKAGE__->meta->make_immutable;
1;
