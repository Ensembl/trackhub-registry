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

my $log_file = "${log_dir}/biosample_ids.log";
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

#
# TODO
# Correct metakey should be communicated
#
my $sample_id_key = 'tissue_type';
my $results = eval {
  $es->search(index  => 'trackhubs',
	      type   => 'trackdb',
	      body   => {
			 # fields => [ $sample_id_key ],
			 query => {
				   filtered => {
						filter => { 'exists' => { field => $sample_id_key }}
					       }
				  }
			});
}; 
if ($@) {
  my $message = "Error querying for track hubs with BioSample IDs: $@";
  send_alert_message($message);
  $logger->logdie($message);
}

my $biosample_ids;
foreach my $doc (@{$results->{hits}{hits}}) {
  map { $biosample_ids->{$_->{$sample_id_key}}++ if exists $_->{$sample_id_key} } @{$doc->{_source}{data}};
} 

print Dumper $biosample_ids;

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

sub send_alert_message {
  my $body = shift;

  my $localtime = localtime;
  my $message = 
    Email::MIME->create(
			header_str => 
			[
			 From    => 'avullo@ebi.ac.uk',
			 To      => 'avullo@ebi.ac.uk',
			 Subject => sprintf("Alert report from TrackHub Registry: %s", $localtime),
			],
			attributes => 
			{
			 encoding => 'quoted-printable',
			 charset  => 'ISO-8859-1',
			},
			body_str => $body,
		       );
  
  $logger->info("Sending alert report to admin");
  sendmail($message);  
}

__END__

=head1 NAME

dump_biosample_ids.pl - Dump to file a list of biosample IDs which are referred to in registered track hubs.

=head1 SYNOPSIS

dump_biosample_ids.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          logdir [default: logs]
   -h --help            display this help and exits

=cut
