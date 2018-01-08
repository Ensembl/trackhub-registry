# Copyright [2015-2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;
use Test::More;
use Test::Deep;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
  $ENV{CATALYST_CONFIG} = "$Bin/../registry_testing.conf";
}

use Data::Dumper;

use_ok 'Registry::Model::Stats';

my $stats = Registry::Model::Stats->new();
isa_ok($stats, 'Registry::Model::Stats');

my $json = $stats->fetch_summary;
cmp_deeply($json, [[ "Element", "", {"role" => "style"} ],
		   [ "Hubs", 1772, "color: gray" ],
		   [ "Species", 89, "color: #76A7FA" ],
		   [ "Assemblies", 102, "opacity: 0.2"]], "basic summary");

done_testing();
