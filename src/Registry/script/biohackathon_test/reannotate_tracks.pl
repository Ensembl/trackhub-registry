#!/usr/bin/env perl
# Copyright [2015-2016] EMBL-European Bioinformatics Institute
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
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Search::Elasticsearch;

# default option values
my $help = 0;  # print usage and exit
my $log_dir = 'logs';
my $config_file = '.initrc'; # expect file in current directory

# parse command-line arguments
my $options_ok = 
  GetOptions("config|c=s" => \$config_file,
	     "logdir|l=s" => \$log_dir,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

# init logging, use log4perl inline configuration
unless(-d $log_dir) {
  mkdir $log_dir or
    die("cannot create directory: $!");
}

my $log_file = "${log_dir}/reannotate.log";
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

#######################################################
#
# Query ES cluster to get the list of BioSample IDs
#
my $es = connect_to_es_cluster($config{cluster_prod});
open my $FH, "<results_by_zooma_with_uri.txt" or die "Cannot open file: $!\n";
my $metadata2terms;
while (my $line = <$FH>) {
  chomp($line);
  my ($key, $value, $term) = split /\t/, $line;
  $value =~ s/^\s//g;
  $metadata2terms->{$key}{$value} = $term;
}

# select a bunch metadata terms, find the corresponding hubs and reannotate them
my @terms = qw / tissue_type dev_stage antibody cell_type ecotype scientific_name CELL_TYPE donor_health_status disease /;
my $term = 'cell_type';
my $results = eval {
  $es->search(index  => 'trackhubs',
  	      type   => 'trackdb',
  	      body   => {
  			 # fields => [ $sample_id_key ],
  			 query => {
  				   filtered => {
  						filter => { 'exists' => { field => $term }}
  					       }
  				  }
  			},
	     size    => 100000);
}; 
if ($@) {
  my $message = "Error querying for track hubs: $@";
  $logger->logdie($message);
}

# print $results->{hits}{total};
my $total_reannotated = 0;
foreach my $doc (@{$results->{hits}{hits}}) {
  # reannotate tracks with the terms found
  my $reannotated = 0;
  foreach my $track_metadata (@{$doc->{_source}{data}}) {
    foreach my $metadata_value (keys %{$metadata2terms->{$term}}) {
      if (exists $track_metadata->{$term} and $track_metadata->{$term} eq $metadata_value) {
	$track_metadata->{ontology_term} = $metadata2terms->{$term}{$metadata_value};
	$reannotated = 1;
      }
    }
  }
  if ($reannotated) {
    $total_reannotated++;
    delete $doc->{_source}{owner};
    delete $doc->{_source}{status};
    delete $doc->{_source}{configuration};
    open my $FH, sprintf ">%s.json", $doc->{_source}{hub}{name} or die "Cannot open file: $!\n";
    print $FH to_json($doc->{_source});
    close $FH;
  }
}

print "\n$total_reannotated\n";

sub connect_to_es_cluster {
  my $cluster_conf = shift;
  my $cluster_name = $cluster_conf->{name};
  my $nodes = $cluster_conf->{nodes};

  $logger->info("Checking the cluster ${cluster_name} is up and running");
  my $esurl;
  if (ref $nodes eq 'ARRAY') {
    $esurl = sprintf "http://%s", $nodes->[0];
  } else {
    $esurl = sprintf "http://%s", $nodes;
  }
  $logger->logdie(sprintf "Cluster %s is not up", $cluster_name)
    unless HTTP::Tiny->new()->request('GET', $esurl)->{status} eq '200';

  $logger->info("Instantiating ES client");
  return Search::Elasticsearch->new(cxn_pool => 'Sniff',
				    nodes => $nodes);
}

__END__

=head1 NAME

dump_biosample_ids.pl - Dump to file a list of biosample IDs which are referred to in registered track hubs.

=head1 SYNOPSIS

dump_metadata.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          logdir [default: logs]
   -h --help            display this help and exits

=cut
