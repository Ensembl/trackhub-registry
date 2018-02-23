#!/usr/bin/env perl
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

use Try::Tiny;
use Log::Log4perl qw(get_logger :levels);
use Config::Std;
use Getopt::Long;
use Pod::Usage;

use Data::Dumper;
use JSON;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request::Common qw/GET POST/;
use Search::Elasticsearch;

# default option values
my $help = 0;  # print usage and exit
my $log_dir = 'logs';
my $cluster_type = 'production';
my $config_file = '.initrc'; # expect file in current directory

# parse command-line arguments
my $options_ok = 
  GetOptions("config|c=s" => \$config_file,
             "logdir|l=s" => \$log_dir,
             "type|t=s"   => \$cluster_type,
             "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

# init logging, use log4perl inline configuration
unless(-d $log_dir) {
  mkdir $log_dir or
    die("cannot create directory: $!");
}

my $log_file = "${log_dir}/dump_stats.log";
my $log_conf = <<"LOGCONF";
log4perl.logger=DEBUG, Screen, File

log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d %p> %F{1}:%L - %m%n

log4perl.appender.File=Log::Dispatch::File
log4perl.appender.File.filename=$log_file
log4perl.appender.File.mode=append
log4perl.appender.File.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.File.layout.ConversionPattern=%d %p> %F{1}:%L - %m%n
LOGCONF

Log::Log4perl->init(\$log_conf);
my $logger = get_logger();

$logger->info("Reading configuration file $config_file");
my %config;
eval {
  read_config $config_file => %config
};
$logger->logdie("Error reading configuration file $config_file: $@") if $@;

my $ua = LWP::UserAgent->new;
my $server = 'https://beta.trackhubregistry.org';

my $cluster;
if ($cluster_type =~ /prod/) {
  $cluster = 'cluster_prod';
} elsif ($cluster_type =~ /stag/) {
  $cluster = 'cluster_staging';
} else {
  $logger->logdie("Unknown type of cluster, should be either 'production' or 'staging'");
}
my $nodes = $config{$cluster}{nodes};

$logger->info("Checking the cluster is up and running");
my $esurl;
if (ref $nodes eq 'ARRAY') {
  $esurl = sprintf "http://%s", $nodes->[0];
} else {
  $esurl = sprintf "http://%s", $nodes;
}
$logger->logdie(sprintf "Cluster %s is not up", $config{$cluster}{name})
  unless HTTP::Tiny->new()->request('GET', $esurl)->{status} eq '200';

$logger->info("Instantiating ES client");
my $es = Search::Elasticsearch->new(cxn_pool => 'Sniff',
                                    nodes => $nodes);

my ($index, $type) = ($config{trackhubs}->{alias}, $config{trackhubs}->{type});

summary_stats();

# Do not enable, more elaborate stats not used at the moment
# collect_stats();

#
# stats per species/assembly/file type
#
# - number of hubs
# - file types
#
sub collect_stats {
  my $request = GET("$server/api/stats/complete");
  my $response = $ua->request($request);
  unless ($response->is_success) {
    my $message = sprintf "Error getting track hubs: %s [%d]", $response->content, $response->code;
    $logger->logdie($message);  
  }
  my $content = from_json($response->content);

  # split the stats into different file components to
  # allow faster retrieval with the model
  foreach my $statsby (qw/species assemblies file_type/) {
    my $outfile = "../../root/static/data/${statsby}.json";
    open my $FH, "$outfile",'w' or $logger->logdie("Cannot open file $outfile: $!");
    print $FH to_json($content->{$statsby});
    close $FH;
  }
}


#
# retrieve global stats for the front page
#
sub summary_stats {
# get the total number of hubs
  my $request = GET("$esurl/$index/$type/_count?q=public:1");
  my $response = $ua->request($request);
  unless ($response->is_success) {
    my $message = sprintf "Error counting for track hubs: %s [%d]", $response->content, $response->code;
    $logger->logdie($message);  
  }

  my $num_hubs = from_json($response->content)->{count};

  # retrieve total number of species/assemblies
  # use /api/info/assemblies endpoint
  $request = GET("$server/api/info/assemblies");
  $response = $ua->request($request);
  my ($num_assemblies, $num_species);
  if ($response->is_success) {
    my $assemblies = from_json($response->content);
    $num_species = scalar keys %{$assemblies};

    $num_assemblies = 0;
    map { $num_assemblies += scalar @{$assemblies->{$_}} } keys %{$assemblies};
  
  } else {
    my $message = sprintf "Error counting for track hubs: %s [%d]", $response->content, $response->code;
    $logger->logdie($message);  
  }

  my $outfile = "../../root/static/data/summary.json";
  open my $FH, "$outfile",'w' or $logger->logdie("Cannot open file $outfile: $!");
  print $FH to_json([
                     ["Element", "Number of Elements", { "role" => "style" } ],
                     ["Hubs", $num_hubs, "color: gray"],
                     ["Species", $num_species, "color: #76A7FA"],
                     ["Assemblies", $num_assemblies, "color: green"]
                    ]);
  close $FH;
}

__END__

=head1 NAME

dump_stats.pl - 

=head1 SYNOPSIS

dump_stats.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          logdir [default: logs]
   -t --type            cluster type (production, staging) [default: production]
   -h --help            display this help and exits

=cut
