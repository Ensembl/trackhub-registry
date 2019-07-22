#!/usr/bin/env perl
# Copyright [2015-2019] EMBL-European Bioinformatics Institute
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
use Scalar::Util qw/looks_like_number/;

use Data::Dumper;
use JSON;
use HTTP::Tiny;
use LWP::UserAgent;
use HTTP::Request::Common qw/GET POST DELETE/;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Search::Elasticsearch;

# to parse UCSC public list
use HTML::DOM;
use File::Temp qw/ tempfile /;
use Registry::Utils::URL qw(read_file);

# default option values
my $help = 0;  # print usage and exit
my $log_dir = '/nfs/public/nobackup/ens_thr/production/public_hubs/logs/';
my $config_file = 'public_hubs.conf'; # expect file in current directory
my $email; # The account to try to send emails to when things go wrong.

# parse command-line arguments
my $options_ok = 
  GetOptions("config|c=s" => \$config_file,
             "logdir|l=s" => \$log_dir,
             "email|c=s" => \$email,
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
#my $server = 'https://beta.trackhubregistry.org';
my $server = 'http://www.trackhubregistry.org/';

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
# 1. Parse UCSC public hub list to complement the list
#    of hubs from the configuration file
#
my $ucsc_public_hubs = parse_ucsc_public_list();

# 
# 2. update configuration with ucsc hubs
#
foreach my $ucsc_hub (@{$ucsc_public_hubs}) {
  my $processed = exists $config{$ucsc_hub->[0]};
  # some might already been in conf from last run or
  # because is in e! public list
  $logger->info(sprintf "UCSC listed Hub \"%s\" already configured for registration", $ucsc_hub->[1]) and next
    if $processed;

  $config{$ucsc_hub->[0]} = 
    {
     enable      => 1,
     description => $ucsc_hub->[1],
    } 
}

#
# 3. Scan list of hubs, and register/update/delete them
#
foreach my $hub_url (keys %config) {
  my %hub_conf = %{$config{$hub_url}};
  my $desc = $hub_conf{description};
  my $enabled = $hub_conf{enable};

  # delete configuration keys to proper content for submission, 
  # only assembly name-accession mapping should be left
  for my $key (qw/description enable permissive error/) {
    delete $hub_conf{$key};
  }

  my $delete = 0;
  my $hub_name = search_hub_by_url($hub_url);
  my $registered = looks_like_number($hub_name) ? 0 : 1;
  $logger->info(sprintf "Found hub \"%s\" [%s,%s]", $desc, $enabled?"enabled":"not enabled", $registered?"registered":"not registered");

  if ($enabled) {
    # hub enabled, proceed with registration/update
    $logger->info("Submitting hub at $hub_url");

    my $content = { url => $hub_url };
    $content->{assemblies} = { %hub_conf } # add assembly name->accession map if available
      if scalar keys %hub_conf;

    my $post_url = "$server/api/trackhub";
    $post_url .= '?permissive=1' if $config{$hub_url}->{permissive};
    $request = POST($post_url,
                    'Content-type' => 'application/json',
                    'Content'      => to_json($content));
    $request->headers->header(user       => $user);
    $request->headers->header(auth_token => $auth_token);
    $response = $ua->request($request);
    if ($response->code == 201) {
      $logger->info("Done");
      delete $config{$hub_url}->{error} if exists $config{$hub_url}->{error};
    } else {
      $logger->logwarn(sprintf "Couldn't register hub at %s: %s [%d]", $hub_url, $response->content, $response->code);
      # hub remains enabled?!
      # Yes, we would like to inspect the reason of the error and eventually take action, e.g. manually disable
      # $config{$hub_url}->{enable} = 0;
      $config{$hub_url}->{error} = sprintf "[%d] - %s", $response->code, $response->content;

      $delete = 1 if $registered; # mark for deletion
    } 
  } else {
    $logger->info(sprintf "Hub %s not enabled. Skip.", $desc);
    $delete = 1 if $registered; # mark for deletion
  }

  # hub is registered but it's flagged for deletion, go ahead
  if ($delete) { 
    $logger->info("Deleting hub $hub_name");
    $request = DELETE("$server/api/trackhub/$hub_name");
    $request->headers->header(user       => $user);
    $request->headers->header(auth_token => $auth_token);
    $response = $ua->request($request);
    if ($response->code == 200) {
      $logger->info("Done");
    } else {
      $logger->logwarn(sprintf "Couldn't delete hub %s: %s [%d]", $hub_name, $response->content, $response->code);
    }
  }
}

#
# 3. Update configuration file with new state
#
write_config(%config);

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
  $logger->info("Parsing UCSC public hub list");
  my $hg_hub_connect_url = 'http://genome-euro.ucsc.edu/cgi-bin/hgHubConnect?redirect=manual&source=genome.ucsc.edu';
  my $response = read_file($hg_hub_connect_url, { nice => 1 });
  $logger->logdie(sprintf "Unable to parse UCSC public hub list: %s", $response->{error}) if $response->{error};

  my ($fh, $filename) = tempfile( DIR => '/nfs/public/nobackup/ens_thr/production/tmp/', SUFFIX => '.html', UNLINK => 1 );
  print $fh $response->{content};
  close $fh;

  my $dom = HTML::DOM->new();
  $dom->parse_file($filename);

  # register hub url and description
  my $hubs;
  foreach my $hub_table_row (@{$dom->getElementById('publicHubsTable')->rows}) {
    my $cells = $hub_table_row->cells;
    next if $cells->item(0)->tagName eq 'TH';
  
    # take link in second column
    my $elem = $cells->item(1);
    my $anchor = $elem->getElementsByTagName('a')->[0];
    # and grab hub url and brief description
    my ($hub_url, $hub_desc) = ($anchor->href, $anchor->content->[0]->data);
    $hub_desc =~ s/^\n//g;
    push @{$hubs}, [ $hub_url, $hub_desc ];
  }

  return $hubs;
}

sub search_hub_by_url {
  my $url = shift;
  my $request = POST("$server/api/search",
                     'Content-type' => 'application/json',
                     'Content'      => to_json({ query => "hub.url:\"$url\"" }));
  my $response = $ua->request($request);
  if ($response->is_success) {
    my $content = from_json($response->content);
    my $num_search_results = scalar @{$content->{items}};

    return 0 if $num_search_results == 0;
    
    # search might return multiple results
    # - hub might be split across different trackDBs
    # - error in data store, multiple hubs with same URL
    my $hub;
    foreach my $item (@{$content->{items}}) {
      my $item_hub = $item->{hub};
      $hub = $item_hub and next unless $hub;

      if (exists $hub->{name} && $hub->{name} ne $item_hub->{name}) {
        $logger->logwarn("Ambiguous results while searching for registered hub");
        return -1;
      }
    }

    return $hub->{name};
  }

  return -1; # don't know at this stage if the hub is registered
}

sub send_alert_message {
  my $body = shift;

  my $localtime = localtime;
  my $message = 
    Email::MIME->create(
      header_str => 
      [
       From    => $email,
       To      => $email,
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
