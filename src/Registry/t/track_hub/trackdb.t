# Copyright [2015-2019] EMBL-European Bioinformatics Institute
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
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use POSIX qw(strftime);
use JSON;

use Registry::Utils;

use_ok 'Registry::TrackHub::TrackDB';

my $parsed_hub_path = "$Bin/plant1.json";
my $hub_json = from_json( Registry::Utils::slurp_file($parsed_hub_path) );
$hub_json->{created} = 100000;
$hub_json->{type} = 'genomic';

my $trackdb = Registry::TrackHub::TrackDB->new(doc => $hub_json);
isa_ok($trackdb, 'Registry::TrackHub::TrackDB');
my $status = $trackdb->status();
is($status->{tracks}{total}, 13, 'Number of tracks');
is($status->{tracks}{with_data}{total}, 12, 'Number of tracks with data');
is($status->{tracks}{with_data}{total_ko}, 0, 'Number of tracks with remote data unavailable');
is($status->{message}, 'Unchecked', 'Status message');

is_deeply($trackdb->file_type, [ 'bigbed', 'bigwig' ], 'File type(s)');

is($trackdb->type, 'genomic', 'Hub type was assigned to object attribute');
is($trackdb->assembly_name, 'JCVI_RCG_1.1', 'Assembly name made accessible via method');
is($trackdb->hub_name, 'cshl2013', 'Hub name made accessible via method');
is($trackdb->version_number, 'v1.0', 'Hub version available via method');

done_testing();
