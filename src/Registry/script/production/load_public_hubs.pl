#!/usr/bin/env perl

use strict;
use warnings;

# for Registry::Utils::URL methods
BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

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

# to parse UCSC public list
use HTML::DOM;
use File::Temp qw/ tempfile /;
use Registry::Utils::URL qw(read_file);

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
parse_ucsc_public_list();

# 2. Scan list of hubs, and register/update/delete them
#
foreach my $hub_url (keys %config) {
  # next unless $hub_url =~ /smith/;
  my %hub_conf = %{$config{$hub_url}};
  my $desc = $hub_conf{description};
  my $enabled = $hub_conf{enable};

  # delete configuration keys, only assembly name-accession mapping should be left
  map { delete $hub_conf{$_} } qw/description enable error/;

  if ($enabled) {
    # hub enabled, proceed with registration/update
    $logger->info("Submitting hub at $hub_url");

    my $content = { url => $hub_url };
    $content->{assemblies} = { %hub_conf } # add assembly name->accession map if available
      if scalar keys %hub_conf;

    $request = POST("$server/api/trackhub",
		    'Content-type' => 'application/json',
		    'Content'      => to_json($content));
    $request->headers->header(user       => $user);
    $request->headers->header(auth_token => $auth_token);
    $response = $ua->request($request);
    if ($response->code == 201) {
      $logger->info("Done");
    } else {
      $logger->logwarn(sprintf "Couldn't register hub at %s: %s [%d]", $hub_url, $response->content, $response->code);
      # hub remains enabled?!
      # $config{$hub_url}->{enable} = 0;
      $config{$hub_url}->{error} = sprintf "[%d] - %s", $response->code, $response->content;
    } 
  } else {
    # hub is not enabled
    # delete it if it's registered
    $logger->info(sprintf "0: %s", $desc);
  } 
}
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

sub parse_ucsc_public_list {
  my $hg_hub_connect_url = 'http://genome-euro.ucsc.edu/cgi-bin/hgHubConnect?redirect=manual&source=genome.ucsc.edu';
  my $response = read_file($hg_hub_connect_url, { nice => 1 });
  $logger->logdie(sprintf "Unable to parse UCSC public hub list: %s", $response->{error}) if $response->{error};

  my ($fh, $filename) = tempfile( DIR => '.', SUFFIX => '.html', UNLINK => 1 );
  print $fh $response->{content};
  close $fh;

  my $dom = HTML::DOM->new();
  $dom->parse_file($filename);

  foreach my $hub_table_row (@{$dom->getElementById('publicHubsTable')->rows}) {
    my $cells = $hub_table_row->cells;
    next if $cells->item(0)->tagName eq 'TH';
  
    # take second column
    my $elem = $cells->item(1);
    my $anchor = $elem->getElementsByTagName ('a')->[0];
    # print $anchor->href, "\t", $anchor->text, "\n";
  }
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
