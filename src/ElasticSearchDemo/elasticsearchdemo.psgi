use strict;
use warnings;

use ElasticSearchDemo;

my $app = ElasticSearchDemo->apply_default_middlewares(ElasticSearchDemo->psgi_app);
$app;

