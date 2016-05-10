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
my $config_file = 'public_hubs.conf'; # expect file in current directory

# parse command-line arguments
my $options_ok = 
  GetOptions("config|c=s" => \$config_file,
	     "logdir|l=s" => \$log_dir,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

my ($user, $pass) = ($ARGV[0], $ARGV[1]);
$user and $pass or die "Undefined user and/or password\n";

# init logging, use log4perl inline configuration
unless(-d $log_dir) {
  mkdir $log_dir or
    die("cannot create directory: $!");
}

my $log_file = "${log_dir}/load_public_hubs.log";
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

# Login
my $ua = LWP::UserAgent->new;
my $server = 'https://beta.trackhubregistry.org';

my $request = GET("$server/api/login");
$request->headers->authorization_basic($user, $pass);
my $response = $ua->request($request);
my $auth_token;
if ($response->is_success) {
  $auth_token = from_json($response->content)->{auth_token};
  $logger->info("Logged in [$user: $auth_token]") if $auth_token;
} else {
  $logger->logdie(sprintf "Couldn't login as user $user: %s [%d]", $response->content, $response->code);
}

#
# TODO
#
# 1. Parse UCSC public hub list to complement the list
#    of hubs from the configuration file
#
# 2. Scan hub list and register them
#
# 3. Update configuration file
#

# Logout
$request = GET("$server/api/logout");
$request->headers->header(user       => $user);
$request->headers->header(auth_token => $auth_token);
if ($response->is_success) {
  $logger->info("Logged out");
} else {
  $logger->logdie("Unable to logout");
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

load_public_hubs.pl - 

=head1 SYNOPSIS

load_public_hubs.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          logdir [default: logs]
   -h --help            display this help and exits

=cut
