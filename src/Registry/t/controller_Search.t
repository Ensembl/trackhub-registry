use strict;
use warnings;
use Test::More;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common qw/GET POST PUT DELETE/;

use Catalyst::Test 'Registry';

use Registry::Utils;
use Registry::Indexer;

# ok( request('/search')->is_success, 'Request should succeed' );

SKIP: {
  skip "Cannot run tests: either elasticsearch is not running or there's no internet connection",
    47 unless &Registry::Utils::es_running() and Registry::Utils::internet_connection_ok();

  note 'Preparing data for test (indexing users)';
  my $config = Registry->config()->{'Model::Search'};
  my $indexer = Registry::Indexer->new(dir   => "$Bin/trackhub-examples/",
						index => $config->{index},
						trackhub => {
						  type  => $config->{type}{trackhub},
						  mapping => 'trackhub_mappings.json'
						},
						authentication => {
						  type  => $config->{type}{user},
						  mapping => 'authentication_mappings.json'
						}
					       );

  # index sample users
  $indexer->index_users();

  # authenticate one of them
  my $request = GET('/api/login');
  $request->headers->authorization_basic('trackhub1', 'trackhub1');
  ok(my $response = request($request), 'Request to log in');
  my $content = from_json($response->content);
  ok(exists $content->{auth_token}, 'Logged in');
  my $auth_token = $content->{auth_token};

  # submit public hubs (from UCSC list)
  # 12 out of 27 hubs cannot be submitted
  # - 7 do not validate
  # - 5 bad requests
  my %public_hubs = (
		     # vizhub  => 'http://vizhub.wustl.edu/VizHub/RoadmapReleaseAll.txt', # memory consumption, does not validate
		     # zhub    => 'http://zlab.umassmed.edu/zlab/publications/UMassMedZHub/hub.txt', # Status Bad Request: 599: Internal Exception at /home/avullo/work/ensembl/trackhub-registry/src/Registry/t/../lib/Registry/TrackHub.pm line 92, <$fh> line 1.

		     polyA   => 'http://johnlab.org/xpad/Hub/UCSC.txt',
		     encode  => 'http://ftp.ebi.ac.uk/pub/databases/ensembl/encode/integration_data_jan2011/hub.txt',
		     mRNA    => 'http://www.mircode.org/ucscHub/hub.txt',
		     dnameth => 'http://smithlab.usc.edu/trackdata/methylation/hub.txt',
		     tis     => 'http://gengastro.1med.uni-kiel.de/suppl/footprint/Hub/tisHub.txt',
		     # sdsu    => 'http://bioinformatics.sdstate.edu/datasets/2012-NAT/hub.txt', # does not validate
		     blueprint => 'ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub',
		     # cemt      => 'http://www.bcgsc.ca/downloads/edcc/data/CEMT/hub/bcgsc_datahub.txt', # does not validate
		     plants    => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/Plants/hub.txt',
		     # broad     => 'https://www.broadinstitute.org/ftp/pub/vgb/dog/trackHub/hub.txt', # does not validate
		     ensembl   => 'http://ngs.sanger.ac.uk/production/ensembl/regulation/hub.txt',
		     mcgill    => 'http://epigenomesportal.ca/hub/hub.txt',
		     ultracons => 'http://genome-test.cse.ucsc.edu/~hiram/hubs/GillBejerano/hub.txt',
		     # fantom5   => 'http://fantom.gsc.riken.jp/5/datahub/hub.txt', # Status Bad Request: File http://fantom.gsc.riken.jp/5/datahub/hg19/trackDb.txt: parent track TSS_peaks_and_counts full is missing at /home/avullo/work/ensembl/trackhub-registry/src/Registry/t/../lib/Registry/TrackHub/Parser.pm line 201, <$fh> line 1.
		     # washu     => 'http://vizhub.wustl.edu/VizHub/RoadmapIntegrative.txt', # does not validate
		     rnaseq    => 'http://web.stanford.edu/~htilgner/2012_454paper/data/hub.txt',
		     zebrafish => 'http://research.nhgri.nih.gov/manuscripts/Burgess/zebrafish/downloads/NHGRI-1/hub.txt',
		     # facebase  => 'http://trackhub.facebase.org/hub.txt', # does not validate
		     phylocsf  => 'http://www.broadinstitute.org/compbio1/PhyloCSFtracks/trackHub/hub.txt',
		     # fantom5c  => 'http://fantom.gsc.riken.jp/5/suppl/Ohmiya_et_al_2014/data/hub.txt', # Status Bad Request: File http://fantom.gsc.riken.jp/5/suppl/Ohmiya_et_al_2014/data/reclu/trackDb.txt: parent track RECLU_clusters full is missing at /home/avullo/work/ensembl/trackhub-registry/src/Registry/t/../lib/Registry/TrackHub/Parser.pm line 201, <$fh> line 1
		     sanger    => 'http://ngs.sanger.ac.uk/production/grit/track_hub/hub.txt',
		     # crocbird  => 'http://hgwdev.cse.ucsc.edu/~jcarmstr/crocBrowserRC2/hub.txt', # Status Bad Request: Unable to find an NCBI assembly id from Anc08 at /home/avullo/work/ensembl/trackhub-registry/src/Registry/t/../lib/Registry/TrackHub/Translator.pm line 680, <$fh> line 1.
		     thornton  => 'http://devlaeminck.bio.uci.edu/RogersUCSC/hub.txt',
		     # cptac     => 'http://openslice.fenyolab.org/tracks/CPTAC/cptac/v1/hub.txt', # does not validate
		     # libd      => 'https://s3.amazonaws.com/DLPFC_n36/humanDLPFC/hub.txt', # Status Bad Request: 400: Bad Request at /home/avullo/work/ensembl/trackhub-registry/src/Registry/t/../lib/Registry/TrackHub.pm line 92.
		    );

  foreach my $hub (keys %public_hubs) {
    note "Submitting hub $hub";
    my $request = POST('/api/trackhub/create',
		       'Content-type' => 'application/json',
		       'Content'      => to_json({ url => $public_hubs{$hub} }));
    $request->headers->header(user       => 'trackhub1');
    $request->headers->header(auth_token => $auth_token);
    ok($response = request($request), 'POST request to /api/trackhub/create');
    ok($response->is_success, 'Request successful 2xx');
    is($response->content_type, 'application/json', 'JSON content type');
  }
		     
}

done_testing();
