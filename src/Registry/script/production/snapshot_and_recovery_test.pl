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

#######################################################
#
# Take snapshot on production cluster
#
my $es = connect_to_es_cluster($config{cluster_prod});

my $snapshot_name = sprintf "snapshot_%s", $date;
# we backup only relevant indices 
my $indices = join(',', qw/trackhubs users reports/);
$logger->info("Creating snapshot ${snapshot_name} of indices $indices");
eval {
  $es->snapshot->create(repository  => $config{repository}{name},
			snapshot    => $snapshot_name,
			body        => {
					indices => $indices
				       });
}; # catch {
if ($@) {
  my $message = "Couldn't take snapshot ${snapshot_name}: $@";
  send_alert_message($message);
  $logger->logdie($message);
}

#};

# monitor snapshot status, cannot proceed to restore
# before it is completed
my $snapshot_status;
do {
  $snapshot_status = $es->snapshot->status(repository  => $config{repository}{name},
					   snapshot    => $snapshot_name)->{snapshots}[0]{state};
} while ($snapshot_status eq 'IN_PROGRESS' or $snapshot_status eq 'STARTED');

unless ($snapshot_status eq 'SUCCESS') {
  my $message = "Taking Snapshot ${snapshot_name failed}";
  send_alert_message($message);
  $logger->logdie($message);
}

#######################################################
#
# Restore from snapshot on staging cluster
#
$es = connect_to_es_cluster($config{cluster_staging});

$logger->info("Closing indices on staging cluster");
eval {$es->indices->close(index => [ split /,/, $indices ]); };
if ($@) {
  my $message = "Failed closing indices on staging server: $@";
  send_alert_message($message);
  $logger->logdie($message);
}

$logger->info("Restoring from snapshot ${snapshot_name}");
# TODO
# - email in case of problem
# NOTE
# the restore API with Search::Elasticsearch client doesn't work
# revert to a simple HTTP call
# eval {
#   $es->snapshot->restore(repository  => $config{repository}{name},
# 			 snapshot    => $snapshot_name,
# 			 body        => {
# 					 indices => $indices
# 					});
# };# catch {
# $logger->logdie("Failed restoration from snapshot ${snapshot_name}: $@") if $@;
#};
my $ua = LWP::UserAgent->new;
my $request = 
  POST(sprintf "http://%s/_snapshot/backup/%s/_restore", $config{cluster_staging}{nodes}, $snapshot_name,
       'Content-type' => 'application/json',
       'Content'      => to_json({ indices => $indices }));
my $response = $ua->request($request);
if ($response->code != 200) {
  my $message = sprintf "Couldn't restore from snapshot ${snapshot_name}:\n%s", from_json($response->content);
  send_alert_message($message);
  $logger->logdie($message);
}
# my $response = 
#   HTTP::Tiny->new()->request('POST', 
# 			     sprintf "http://%s/_snapshot/backup/%s/_restore", $config{cluster_staging}{nodes}, $snapshot_name, 
# 			     { content => { indices => $indices } });

$logger->info("Monitor restoring process");
sleep 5;
eval {
  my ($response, $restore_status);
  my $complete = 1;
  do {
    # $response = HTTP::Tiny->new()->request('GET', sprintf "http://%s/_cat/recovery?v", $config{cluster_staging}{nodes});
    # $response = HTTP::Tiny->new()->request('GET', sprintf "http://%s/_recovery?pretty&human", $config{cluster_staging}{nodes});
    # print Dumper $response; exit;

    my $request = GET(sprintf "http://%s/_recovery?pretty&human", $config{cluster_staging}{nodes});
    $response = $ua->request($request);
    die "Couldn't query the recovery endpoint for status"
      unless $response->code == 200;

    my $info;

    #
    # this is to parse the response to the cat API call
    #
    # open my $FH, '<', \$response or die "Cannot read response: $!\n";
    # <$FH>; # first line is header
    # while (my $line = <$FH>) {
    #   chomp ($line);
    #   next if $line =~ /^\s/;
    #   my ($index, $shard, $time, $type, $stage, $source_host, $target_host, $repository, $snapshot, $files, $files_percent, $bytes, $bytes_percent, $total_files, $total_bytes, $translog, $translog_percent, $total_translog) =
    #     split /\s+/, $line;
    #   $info->{$index}{$shard} = $stage;
    #   print "$index\t$shard\t$stage\n";
    # }
    # close $FH;

    # foreach my $index (keys %{$info}) {
    #   foreach my $shard (keys %{$info->{$index}}) {
    #     # we die if we get unexpected stage so that we
    #     # can interrupt the monitoring process
    #     my $stage = $info->{$index}{$shard};
    #     die "Something unexpected happened during recovery, stage: $stage"
    # 	unless ($stage eq 'done' or $stage eq 'index' or $stage eq 'init');
    #     return 0 if $info->{$index}{$shard} ne 'done';
    #   }
    # }

    my $content = eval { from_json($response->content); };
    die "Could't parse recovery endpoint status response: $@" if $@;
    
    # print Dumper $content; 

  OUTER:
    foreach my $index (keys %{$content}) {
      foreach my $shard (@{$content->{$index}{shards}}) {
	# we die if we get unexpected stage so that we
	# can interrupt the monitoring process
	my $stage = $shard->{stage};
	die "Something unexpected happened during recovery, stage: $stage"
	  unless ($stage eq 'DONE' or $stage eq 'INDEX' or $stage eq 'INIT');
	if ($stage ne 'DONE') {
	  $complete = 0;
	  last OUTER;
	}

      }
    }
  } while (not $complete); # not restore_complete($response->content));
};
if ($@) {
  my $message = "Something went wrong monitoring recovering from snapshot ${snapshot_name}:\n$@";
  send_alert_message($message);
  $logger->logdie($message);
}


# $logger->info("Reopening indices");
# $es->indices->open(index => [ split /,/, $indices ]);

$logger->info("DONE.");

sub restore_complete {
  my $response = shift;
  my $info;

  #
  # this is to parse the response to the cat API call
  #
  # open my $FH, '<', \$response or die "Cannot read response: $!\n";
  # <$FH>; # first line is header
  # while (my $line = <$FH>) {
  #   chomp ($line);
  #   next if $line =~ /^\s/;
  #   my ($index, $shard, $time, $type, $stage, $source_host, $target_host, $repository, $snapshot, $files, $files_percent, $bytes, $bytes_percent, $total_files, $total_bytes, $translog, $translog_percent, $total_translog) =
  #     split /\s+/, $line;
  #   $info->{$index}{$shard} = $stage;
  #   print "$index\t$shard\t$stage\n";
  # }
  # close $FH;

  # foreach my $index (keys %{$info}) {
  #   foreach my $shard (keys %{$info->{$index}}) {
  #     # we die if we get unexpected stage so that we
  #     # can interrupt the monitoring process
  #     my $stage = $info->{$index}{$shard};
  #     die "Something unexpected happened during recovery, stage: $stage"
  # 	unless ($stage eq 'done' or $stage eq 'index' or $stage eq 'init');
  #     return 0 if $info->{$index}{$shard} ne 'done';
  #   }
  # }

  my $content = from_json($response);
  return 0 unless $content;

  foreach my $index (keys %{$content}) {
    foreach my $shard (@{$content->{shards}}) {
      # we die if we get unexpected stage so that we
      # can interrupt the monitoring process
      my $stage = $shard->{stage};
      print "$index\t", $shard->{id}, "\t$stage\n"; 
      die "Something unexpected happened during recovery, stage: $stage"
  	unless ($stage eq 'DONE' or $stage eq 'INDEX' or $stage eq 'INIT');
      return 0 if $stage ne 'DONE';
    }
  }

  return 1;
}

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
  return Search::Elasticsearch->new(nodes => $nodes);
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

snapshot_and_recovery_test.pl - Take a snapshot of the data and test the recovery

=head1 SYNOPSIS

snapshot_and_recovery_test.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          logdir [default: logs]
   -h --help            display this help and exits

=cut
