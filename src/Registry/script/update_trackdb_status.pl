#!/usr/bin/env perl

use strict;
use warnings;

use Try::Tiny;
use Getopt::Long;
use Pod::Usage;
use Config::Std;

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

# parse configuration file
my %config;
try {
  read_config $conf_file => %config
} catch {
  FATAL "Error reading configuration file $conf_file";
  FATAL "$@" if $@;
};

# TODO: set up logging
# my $logconf = $config{update}{log};
# Log::Log4perl->init($log_conf);
# my $logger = get_logger();

#
# TODO: handle monitoring options
#
# fetch from ES stats about last run
# --> store different type: check,
#     get latest in time
#
# spawn a separate process for each user or 
# batch of users if their number becomes huge
#
# foreach user (excluded admin)
#   get monitoring configuration
#
#   fetch from ES stats about last check for user:
#   {
#     time: ...,
#     alerts: [ trackdb_id1, ..., trackdb_idn ],
#     sent: true/false
#   }
#
#   skip if check_option is weekly|monthly
#   and (current_time-last_check_time) < week|month
#
#   get the list of trackdbs of the user
#
#   create alert report --> check type
#
#   foreach trackdb
#     try { update trackdb status }
#     catch {
#       log exception (either pending update or another)
#       next
#     }
#     add problem to alert report if problem
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
