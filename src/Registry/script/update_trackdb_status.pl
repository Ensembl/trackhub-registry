#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../lib";
}

use Try::Tiny;
use JSON;
use Getopt::Long;
use Pod::Usage;
# use Config::Std;
use File::Temp qw/ tempfile /;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Data::Dumper;

use Registry::Model::Search;
use Registry::TrackHub::TrackDB;
use Registry::TrackHub::Translator;
use Registry::TrackHub::Validator;
use Registry::Utils::Arrays qw( remove_duplicates union_intersection_difference );

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

my $es = Registry::Model::Search->new();
my $config = Registry->config()->{'Model::Search'};
#
# fetch from ES stats about last run report
# --> store different type: check,
#     get latest in time
#
# {
#   user1: ...,
#   ...
#   usern: ...
# }
#
# NOTE: if we've got no report this is the first run
#
my $last_report = $es->get_latest_report;
my $last_report_id = $last_report->{_id};
$last_report = $last_report->{_source};

# create new run global report
my $current_report = {};

#
# TODO
# - spawn a separate process for each user or 
#   batch of users if their number becomes huge
# - log all steps
#
# foreach user
#   next if user is admin
my $admin;
foreach my $user (@{$es->get_all_users}) {
  my $username = $user->{username};
  if ($username =~ /admin/) {
    $admin = $user;
    next;
  }

  # get monitoring configuration
  my $check_interval = $user->{check_interval};
  my $continuous_alert = $user->{continuous_alert};

  # get last report for user
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
  my $last_user_report = $last_report->{$username};

  # if check_option is weekly|monthly and (current_time-last_check_time) < week|month
  #   copy last user report to new global report
  #   skip check
  if (defined $last_user_report and $check_interval) { # check_interval == 0 -> Automatic so do the check
    my $current_time = time;
    my $last_check_time = $last_user_report->{end_time};
    defined $last_check_time or 
      die "Undefined last_check_time for user $username";
    # check_interval == 1 -> week, 2 -> month
    my $time_interval = $check_interval==1?604800:2592000;

    if ($current_time - $last_check_time < $time_interval) {
      $current_report->{$username} = $last_user_report;
      next;
    }
  }

  # get the list of trackdbs of the user
  my @trackdbs;
  map { push @trackdbs, Registry::TrackHub::TrackDB->new($_->{_id}) }
    @{$es->search_trackhubs(size => 1000000, query => { term => { owner => $username } })->{hits}{hits}};
  
  # skip if the user doesn't have any trackdb yet
  next unless scalar @trackdbs;

  # create user specific report
  my $current_user_report = { start_time => time };

  # loop over trackdbs
  #   update doc if the source has changed
  #   check status
  #   format message along the way
  my ($message_body_update, $message_body_problem);
  my $trackdb_update = 0;

  foreach my $trackdb (@trackdbs) {
    my $source = $trackdb->source;
    if ($source) {
      # trackdb doc has been created from remote public UCSC Hub:
      # check if it's been updated (use checksum), and if it has,
      # update the corresponding document
      try {
	# checksum is not enforced in schema, but it must exist once
	# the remote hub JSON has been submitted
	defined $source->{url} and defined $source->{checksum}
	  or die sprintf "Doc %d source doesn't have url/checksum attributes", $trackdb->id;

	my $checksum = $trackdb->compute_checksum;
       
	if ($checksum and $checksum ne $source->{checksum}) {
	  $trackdb_update = 1;
	  $message_body_update .= sprintf "Detected trackDB [%s] source URL update: ";

	  my $translator = Registry::TrackHub::Translator->new(version => $trackdb->version);
	  my $updated_json_doc = $translator->translate($trackdb->hub->{url}, $trackdb->assembly->{synonyms} || 'unknown')->[0];

	  # validate according to version of original doc
	  my $validator = 
	    Registry::TrackHub::Validator->new(schema => Registry->config()->{TrackHub}{schema}{$trackdb->version});
	  my ($fh, $filename) = tempfile( DIR => '.', SUFFIX => '.json', UNLINK => 1); print $fh $updated_json_doc; close $fh;
	  $validator->validate($filename);

	  my $updated_doc = from_json($updated_json_doc);

	  # TODO? Prevent submission of duplicate content
	  # i.e. trackdb with same hub/assembly
	  # it shouldn't be the case
	  
	  # set the owner/created/updated/status/source attributes
	  $updated_doc->{owner} = $username;
	  $updated_doc->{created} = $trackdb->created;
	  $updated_doc->{updated} = time;
	  $updated_doc->{status}{message} = 'Unknown';
	  $updated_doc->{source}{checksum} = $checksum;

	  # reindex and refresh
	  $es->index(index   => $config->{index},
		     type    => $config->{type}{trackhub},
		     id      => $trackdb->id,
		     body    => $updated_doc);
	  $es->indices->refresh(index => $config->{index});

	  # re-instantiate the trackdb since the document has changed
	  $trackdb = Registry::TrackHub::TrackDB->new($trackdb->id);

	  $message_body_update .= "SUCCESS.\n\n";
	}
      } catch {
	die "Couldn't update doc [%d] for remote trackDb %s\n$@", $trackdb->id, $source->{url};

	$message_body_update .= "ERROR.\n$@\n";

	# we simply skip update and the status check
	next;
      };
    }
    
    # check trackdb status
    my $status;
    try {
      $status = $trackdb->update_status();
    } catch {
      # TODO: log exception (either pending update or another, e.g. timeout)
      die sprintf "Die checking trackdb %s, should log then\n$@", $trackdb->id;

      $message_body_problem .= "Problem updating status for trackDB [%s]\n$@\n\n", $trackdb->id;
      next;
    };
   
    # if problem add trackdb to user report
    if ($status->{tracks}{with_data}{total_ko}) {
      $current_user_report->{ko}{$trackdb->id} =
	$status->{tracks}{with_data}{ko};

      $message_body_problem .= sprintf "trackDB [%d] (%s, %s)\n", $trackdb->id, $trackdb->hub->{name}, $trackdb->assembly->{accession};
      foreach my $track (keys %{$current_user_report->{ko}{$trackdb->id}}) {
	$message_body_problem .= sprintf "\t%s\t%s\t%s\n", $track, $current_user_report->{ko}{$trackdb->id}{$track}[0], $current_user_report->{ko}{$trackdb->id}{$track}[1];
      }
      $message_body_problem .= "\n\n";
    } else {
      push @{$current_user_report->{ok}}, $trackdb->id;
    }
  }

  $current_user_report->{end_time} = time;
  
  if ($trackdb_update or scalar keys %{$current_user_report->{ko}}) { # user trackdbs have problems
    # format complete message body
    my $message_body = "This alert report has been automatically generated durint the last update of the TrackHub Registry.\n\n";
    $message_body .= $message_body_update . "\n\n" . $message_body_problem;
    
    my $message = 
      Email::MIME->create(
			  header_str => 
			  [
			   From    => 'admin@trackhubregistry.org',
			   To      => $user->{email},
			   Subject => 'Alert report from TrackHub Registry',
			  ],
			  attributes => 
			  {
			   encoding => 'quoted-printable',
			   charset  => 'ISO-8859-1',
			  },
			  body_str => $message_body,
			 );

    # check whether we have to send an alert 
    # to the user and send it, eventually
    if ($last_user_report) {
      if ($continuous_alert) {
	# user wants to be continuously alerted: send message anyway 
	sendmail($message);
      } else {
	# user doesn't want to be bothered more than once with the same problems
	# send alert only if current report != last report
	if ($last_user_report->{ko}) {
	  my @last_report_ko_trackdbs = keys %{$last_user_report->{ko}};
	  my @current_report_ko_trackdbs = keys %{$current_user_report->{ko}};
	  my ($union, $isect, $diff) = 
	    union_intersection_difference(@current_report_ko_trackdbs, @last_report_ko_trackdbs);
	  
	  sendmail($message) if scalar @{$diff};
	}
      }
    } else {
      # send alert since this is the first check for this user
      sendmail($message);
    }

  }

  # add user report to global report
  $current_report->{$username} = $current_user_report;
}
   
# store global report
defined $admin or die "Unable to find admin user";

my $message_body;
if ($current_report) {
  my $current_report_id = $last_report_id?++$last_report_id:1;
  $es->index(index   => $config->{index},
	     type    => $config->{type}{report},
	     id      => $current_report_id,
	     body    => $current_report);
  $es->indices->refresh(index => $config->{index});
  $message_body .= sprintf "Report [%d] has been generated.\n\n", $current_report_id;
  
} else {
  $message_body .= "Report has not been generated.\nReason: no users.\n";
}

#
# send alert to admin
my $message = 
  Email::MIME->create(
		      header_str => 
		      [
		       From    => 'admin@trackhubregistry.org',
		       To      => $admin->{email},
		       Subject => sprintf "Alert report from TrackHub Registry: %s", localtime,
		      ],
		      attributes => 
		      {
		       encoding => 'quoted-printable',
		       charset  => 'ISO-8859-1',
		      },
		      body_str => $message_body,
		     );

sendmail($message);

__END__

=head1 NAME

update_trackdb_status.pl - Check trackdb tracks and notify its owners

=head1 SYNOPSIS

update_trackdb_status.pl [options]

   -c --config          configuration file [default: .configrc]
   -h --help            display this help and exits

=cut
