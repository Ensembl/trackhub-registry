#!/usr/bin/env perl

use strict;
use warnings;

use Try::Tiny;
use Log::Log4perl qw(get_logger :levels);
use Config::Std;
use Getopt::Long;
use Pod::Usage;

use Data::Dumper;
use HTTP::Tiny;
use Search::Elasticsearch;

# default option values
my $help = 0;  # print usage and exit
my $config_file = '.initrc'; # expect file in current directory

# parse command-line arguments
my $options_ok = 
  GetOptions("config|c=s" => \$config_file,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

# init logging, use log4perl inline configuration
my $date = `date '+%F'`; chomp($date);
my $log_file = sprintf "init_cluster_%s.log", $date;

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

$logger->info("Checking the cluster is up and running");
my $esurl;
if (ref $config{cluster}{nodes} eq 'ARRAY') {
  $esurl = sprintf "http://%s", $config{cluster}{nodes}[0];
} else {
  $esurl = sprintf "http://%s", $config{cluster}{nodes};
}
$logger->logdie(sprintf "Cluster %s is not up", $config{cluster}{name})
  unless HTTP::Tiny->new()->request('GET', $esurl)->{status} eq '200';

$logger->info("Instantiating ES client");
my $es = Search::Elasticsearch->new(nodes => $config{cluster}{nodes});

$logger->info("Deleting existing indices/aliases");
my $response = $es->indices->get(index => '_all', feature => '_aliases');
my @indices = keys %{$response};
my @aliases = map { keys $response->{$_}{aliases} } @indices;
if (scalar @indices) {
  try {
    $es->delete(index => \@indices);
  } catch {
    $logger->logdie("Couldn't delete existing indices: $_");
  };
} else {
  $logger->info("Empty index list: none deleted");
}

# TODO: delete aliases

foreach my $index_type (qw/trackhubs users reports/) {
  my $index = $config{$index_type}{index};
  $logger->logdie("Unable to get index name for $index_type");
  $logger->info("Creating index $index for $index_type");
  
}



__END__

=head1 NAME

init_cluster.pl - Set up Elasticsearch cluster, make it ready for production 

=head1 SYNOPSIS

init_cluster.pl [options]

   -c --config          configuration file [default: ./configrc]
   -h --help            display this help and exits

=cut
