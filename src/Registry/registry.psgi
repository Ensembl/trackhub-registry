use strict;
use warnings;

use Registry;

my $app = Registry->apply_default_middlewares(Registry->psgi_app);
$app;

