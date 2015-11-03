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
my $es = Search::Elasticsearch->new(cxn_pool => 'Sniff',
				    nodes => $config{cluster}{nodes});

$logger->info("Deleting existing indices/aliases");
my $response = $es->indices->get(index => '_all', feature => '_aliases');
my @indices = keys %{$response};
if (scalar @indices) {
  try {
    map { my $index = $_; 
	  map { $logger->info("Deleting alias $_") and 
		  $es->indices->delete_alias(index => $index,
					     name  => $_) } keys %{$response->{$index}{aliases}};
	} @indices;
  } catch {
    $logger->logdie("Couldn't delete existing index/alias: $_");
  };

  try {
    $es->indices->delete(index => \@indices) and $logger->info("Deleted indices: @indices");
  } catch {
    $logger->logdie("Couldn't delete existing indices: $_");
  };
} else {
  $logger->info("Empty index list: none deleted");
}

$logger->info("Creating index structure");
foreach my $index_type (qw/trackhubs users reports/) {
  my $index = $config{$index_type}{index};
  $logger->logdie("Unable to get index name for $index_type") unless $index;

  $logger->info("Creating index $index for $index_type");
  my $settings;
  $settings->{number_of_shards} = $config{$index_type}{number_of_shards}
    if exists $config{$index_type}{number_of_shards};
  $settings->{number_of_replicas} = $config{$index_type}{number_of_replicas}
    if exists $config{$index_type}{number_of_replicas};

  try {
    if ($settings) {
      $es->indices->create(index => $index, 
			   body  => { settings => $settings }) if $settings;
    } else {
      $es->indices->create(index => $index);
    }
  } catch {
    $logger->logdie("Couldn't create index $index: $_");
  };

  if (exists $config{$index_type}{mapping}) {
    my $type = $config{$index_type}{type};
    $logger->logdie("Unable to get type for index $index") unless $type;
    $logger->info("Creating mapping for type $type on index $index");
    try {
      $es->indices->put_mapping(index => $index,
				type  => $type,
				body  => from_json(slurp_file($config{$index_type}{mapping})));				
    } catch {
      $logger->logdie("Couldn't put mapping on index $index: $_");
    };
  }

  $logger->info("Creating aliases on index $index");
  try {
    $es->indices->put_alias(index => $index,
			    name  => $config{$index_type}{alias});
  } catch {
    $logger->logdie("Couldn't add alias to index $index: $_");
  };
}

$logger->info("Creating admin user");
my $admin_user = 
  {
   id          => 1,
   first_name  => "Alessandro",
   last_name   => "Vullo",
   affiliation => "EMBL-EBI",
   email       => "avullo\@ebi.ac.uk",
   fullname    => "Alessandro Vullo",
   password    => $config{users}{admin_pass},
   roles       => ["admin", "user"],
   username    => $config{users}{admin_name},
  };
try {
  $es->index(index => $config{users}{alias},
	     type  => $config{users}{type},
	     id    => $admin_user->{id},
	     body  => $admin_user);
} catch {
  $logger->logdie("Unable to index admin user: $_");
};

$logger->info("DONE.");

sub slurp_file {
  my $file = shift;
  defined $file or $logger->logdie("Undefined file");

  my $string;
  {
    local $/=undef;
    open FILE, "<$file" or $logger->logdie("Couldn't open file: $!");
    $string = <FILE>;
    close FILE;
  }
  
  return $string;
}

__END__

=head1 NAME

init_cluster.pl - Set up Elasticsearch cluster, make it ready for production 

=head1 SYNOPSIS

init_cluster.pl [options]

   -c --config          configuration file [default: .initrc]
   -h --help            display this help and exits

=cut
