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

=head1 CONTACT

Please email comments or questions to the Trackhub Registry help desk
at C<< <http://www.trackhubregistry.org/help> >>

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Controller::Biodalliance

=head1 DESCRIPTION

Provide an action to show a trackhub in the embeddable Biodalliance browser.

=cut

package Registry::Controller::Biodalliance;
use Moose;
use namespace::autoclean;

use Try::Tiny;
use Catalyst::Exception;

BEGIN { extends 'Catalyst::Controller'; }


=head1 METHODS

=head2 view_biodalliance


=cut

sub view_biodalliance :Path('view') Args(0) {
  my ($self, $c) = @_;
  my $params = $c->req->params;

  my $coord_system =
    {
     speciesName => 'Human',
     taxon => 9606,
     auth => 'GRCh',
    };
  my $genome_source = { name => 'Genome', tier_type => 'sequence' };
  my $gene_source = { name => 'Genes' };

  $c->go('ReturnError', 'custom', ["Must provide assembly"])
    unless exists $params->{assembly};
  $c->go('ReturnError', 'custom', ["Must provide hub URL"])
    unless exists $params->{url};

  my ($chr, $viewStart, $viewEnd, $cookieKey);
  if ($params->{assembly} eq 'hg19') {
    $chr = 22;
    $viewStart = 29890000;
    $viewEnd = 30050000;
    $cookieKey = 'human37';
    
    $coord_system->{speciesName} = 'Human';
    $coord_system->{taxon} = 9606;
    $coord_system->{auth} = 'GRCh';
    $coord_system->{version} = '37';
    $coord_system->{ucscName} = 'hg19';

    $genome_source->{twoBitURI} = '//www.biodalliance.org/datasets/hg19.2bit';

    $gene_source->{desc} = 'Gene structures from GENCODE 19';
    $gene_source->{bwgURI} = '//www.biodalliance.org/datasets/gencode.bb';
    $gene_source->{stylesheet_uri} = '//www.biodalliance.org/stylesheets/gencode.xml';
    $gene_source->{trixURI} = '//www.biodalliance.org/datasets/geneIndex.ix';
    
  } elsif ($params->{assembly} eq 'hg38') {
    $chr = 22;
    $viewStart = 29890000;
    $viewEnd = 30050000;
    $cookieKey = 'human38';
    
    $coord_system->{speciesName} = 'Human';
    $coord_system->{taxon} = 9606;
    $coord_system->{auth} = 'GRCh';
    $coord_system->{version} = '38';
    $coord_system->{ucscName} = 'hg38';

    $genome_source->{twoBitURI} = 'https://www.biodalliance.org/datasets/hg38.2bit';

    $gene_source->{desc} = 'Gene structures from GENCODE 21';
    $gene_source->{bwgURI} = 'https://www.biodalliance.org/datasets/GRCh38/gencode.v21.annotation.bb';
    $gene_source->{stylesheet_uri} = '//www.biodalliance.org/datasets/gencode.bb';
    $gene_source->{trixURI} = 'https://www.biodalliance.org/datasets/GRCh38/gencode.v21.annotation.ix';
    
  } elsif ($params->{assembly} eq 'mm10') {
    $chr = 19;
    $viewStart = 30000000;
    $viewEnd = 30100000;
    $cookieKey = 'mouse38';
    
    $coord_system->{speciesName} = 'Mouse';
    $coord_system->{taxon} = 10090;
    $coord_system->{auth} = 'GRCm';
    $coord_system->{version} = '38';
    $coord_system->{ucscName} = 'mm10';

    $genome_source->{twoBitURI} = '//www.biodalliance.org/datasets/GRCm38/mm10.2bit';

    $gene_source->{desc} = 'Gene structures from GENCODE M2';
    $gene_source->{bwgURI} = '//www.biodalliance.org/datasets/GRCm38/gencodeM2.bb';
    $gene_source->{stylesheet_uri} = '//www.biodalliance.org/stylesheets/gencode.xml';
    $gene_source->{trixURI} = '//www.biodalliance.org/datasets/GRCm38/gencodeM2.ix';
    
  } else {
    $c->go('ReturnError', 'custom', [ sprintf "Assembly %s not supported for biodalliance view", $params->{assembly}])
  }
  
  my $browser =
    {
     chr =>        $chr,
     viewStart =>  $viewStart,
     viewEnd =>    $viewEnd,
     cookieKey =>  $cookieKey,
     coordSystem => $coord_system,
     sources => { genome => $genome_source, genes => $gene_source },
     hub => { name => $params->{name}, url => $params->{url} }
    };
  
  $c->stash(browser => $browser, template  => "search/view_biodalliance.tt");
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

__PACKAGE__->meta->make_immutable;

1;
