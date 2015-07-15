use strict;
use warnings;
use Test::More;


BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

use_ok 'Registry::Model::GenomeAssemblyDB';

# use Registry;
# my $config = Registry->config()->{'Model::GenomeAssemblyDB'};
# use Data::Dumper; print Dumper($config);

done_testing();
