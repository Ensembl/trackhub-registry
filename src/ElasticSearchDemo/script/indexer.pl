#!/usr/bin/env perl

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/lib";
  # use RestHelper;
  # $ENV{CATALYST_CONFIG} = "$Bin/../ensembl_rest_testing.conf";
  # $ENV{ENS_REST_LOG4PERL} = "$Bin/../log4perl_testing.conf";
}

my $es = ElasticSearchDemo::Model::Search->new();
