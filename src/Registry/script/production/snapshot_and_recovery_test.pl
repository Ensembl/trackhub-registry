#!/usr/bin/env perl

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
my $date = `date '+%F'`; chomp($date);
my $log_file = "${log_dir}/snapshots.log";

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

my $es = connect_to_es_cluster($config{cluster_prod});

my $snapshot_name = sprintf "snapshot_%s", $date;
# we backup only relevant indices 
my $indices = join(',', qw/trackhubs users reports/);
$logger->info("Creating snapshot ${snapshot_name} of indices $indices");
# TODO
# - monitor progress
# - email in case of problem
try {
  $es->snapshot->create(repository  => $config{repository}{name},
			snapshot    => $snapshot_name,
			body        => {
					indices => $indices
				       });
} catch {
  $logger->logdie("Couldn't take snapshot ${snapshot_name}: $!");
};

$es = connect_to_es_cluster($config{cluster_staging});

$logger->info("Closing indices on staging cluster");
eval {$es->indices->close(index => [ split /,/, $indices ]); };
$logger->logdie("Failed closing indices on staging server: $@") if $@;

$logger->info("Restoring from snapshot ${snapshot_name}");
# TODO
# - monitor progress
# - email in case of problem
eval {
  $es->snapshot->restore(repository  => $config{repository}{name},
			 snapshot    => $snapshot_name,
			 body        => {
					 indices => $indices
					});
};# catch {
$logger->logdie("Failed restoration from snapshot ${snapshot_name}: $@") if $@;
#};

# should wait untile restoration completes
# $logger->info("Reopening indices");
# $es->indices->open(index => [ split /,/, $indices ]);

$logger->info("DONE.");

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

snapshot_and_recovery_test.pl - Take a snapshot of the data and test the recovery

=head1 SYNOPSIS

snapshot_and_recovery_test.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          logdir [default: logs]
   -h --help            display this help and exits

=cut
