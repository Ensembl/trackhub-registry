#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  # use RestHelper;
  # $ENV{CATALYST_CONFIG} = "$Bin/../ensembl_rest_testing.conf";
  # $ENV{ENS_REST_LOG4PERL} = "$Bin/../log4perl_testing.conf";
}

use Registry::Indexer;

@ARGV == 1 or die "Usage: index_sample_documents.pl <dir>";

my $indexer = Registry::Indexer->new(dir   => $ARGV[0],
				     index => 'test',
				     type  => 'trackhub',
				     mapping => 'trackhub_mappings.json');
$indexer->index();
