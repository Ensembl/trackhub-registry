#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}


use Try::Tiny;
use Getopt::Long;
use Pod::Usage;
# use Config::Std;

use Data::Dumper;

use Registry::Model::Search;

# TODO: set up logging
# use Log::Log4perl qw(get_logger :levels);
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($FATAL);

# default option values
my $help = 0;
my $log_conf = '.logrc';
my $conf_file = '.configrc'; # expect file in current directory

# parse command-line arguments
my $options_ok =
  GetOptions("config|c=s" => \$conf_file,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

# # parse configuration file
# my %config;
# try {
#   read_config $conf_file => %config
# } catch {
#   FATAL "Error reading configuration file $conf_file";
#   FATAL "$@" if $@;
# };

# # TODO: set up logging
# # my $logconf = $config{update}{log};
# # Log::Log4perl->init($log_conf);
# # my $logger = get_logger();

#
# fetch from ES stats about last run report
# --> store different type: check,
#     get latest in time
#
# {
#   start_time: ...,
#   end_time: ...,
#   user1: ...,
#   ...
#   usern: ...
# }

my $es = Registry::Model::Search->new();
my $config = Registry->config()->{'Model::Search'};
my $last_report = $es->get_latest_report;
# NOTE: if we've got no report it's the first run

#
# create new run global report
my $report = {};
#
# TODO: spawn a separate process for each user or 
#       batch of users if their number becomes huge
#
# foreach user
#   next if user is admin
#			
#   get monitoring configuration
#
#   get last report for user:
#   {
#     start_time: ...,
#     end_time: ...,
#     trackdb_id1: {
#                   status: ...,
#                   alert_sent: true/false
#                  },
#     ...,
#     trackdb_idn: { ... }
#   }
#
#   if check_option is weekly|monthly and 
#      (current_time-last_check_time) < week|month
#     copy last user report to new global report
#     next
#
#   get the list of trackdbs of the user
#
#   create user specific report
#
#   foreach trackdb
#     if trackdb has source
#       compute new checksum from url
#       compare checksum with stored one
#       if checksums are different
#         update trackdb document
#
#     try { update trackdb status }
#     catch {
#       log exception (either pending update or another, e.g. timeout)
#     }
#     if problem
#       add trackdb to user report
#       if trackdb was not in last report or
#          trackdb status is different from that of last report
#         send alert and register transmission
#
#   add user report to global report
#   
# store global report
#
# send alert to admin
#  
#
__END__

=head1 NAME

update_trackdb_status.pl - Check trackdb tracks and notify its owner

=head1 SYNOPSIS

update_trackdb_status.pl [options]

   -c --config          configuration file [default: .configrc]
   -h --help            display this help and exits

=cut
