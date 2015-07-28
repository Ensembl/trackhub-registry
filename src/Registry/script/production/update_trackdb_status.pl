#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
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

my $logger = get_logger();

# default option values
my $help = 0;
# my $log_conf = '.logrc';
my $log_dir = 'trackdb_check';
my $conf_file = '.configrc'; # expect file in current directory

# parse command-line arguments
my $options_ok =
  GetOptions(# "config|c=s" => \$conf_file,
	     "logdir|l=s" => \$log_dir,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

# set up logging
unless(-d $log_dir) {
  $logger->info("Creating log directory $log_dir");
  mkdir $log_dir or
    $logger->logdie("cannot create directory: $!");
}

# use Log::Log4perl qw(:easy);
# Log::Log4perl->easy_init($FATAL);
#
use Log::Log4perl qw(get_logger :levels);
# my $log_conf = $config{update}{log};
# Log::Log4perl->init($log_conf);
#
# use inline configuration
my $date = `date '+%F'`; chomp($date);
my $log_file = sprintf "$log_dir/%s.log", $date;

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

# # parse configuration file
# my %config;
# try {
#   read_config $conf_file => %config
# } catch {
#   FATAL "Error reading configuration file $conf_file";
#   FATAL "$@" if $@;
# };

$logger->info("Instantiating document store client");
my $es = Registry::Model::Search->new();
my$config = Registry->config()->{'Model::Search'};
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
my $last_report;
my $last_report_id;
my ($users, $admin);

$logger->info("Getting latest report and user lists");
try {
  $last_report = $es->get_latest_report;
  $last_report_id = $last_report->{_id};
  $last_report = $last_report->{_source};

  $users = $es->get_all_users;
  map { $_->{username} =~ /admin/ and $admin = $_ } @{$users};
} catch {
  $logger->logdie($_);
};

$admin or $logger->logdie("Unable to find admin user.");

# create new run global report
my $current_report = {};

#
# TODO
# - spawn a separate process for each user or 
#   batch of users if their number becomes huge
# - log all steps
#
# for each user
#   update/check its trackdbs
#   notify
foreach my $user (@{$users}) {
  my $username = $user->{username};
  if ($username =~ /admin/) {
    $logger->info("User admin. SKIP.");
    next;
  }

  $logger->info("Working on user $username");

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
    $logger->info(sprintf "%s opts for %s checks. Checking report time interval", $username, $check_interval==1?'weekly':'monthly');
    my $current_time = time;
    my $last_check_time = $last_user_report->{end_time};
    defined $last_check_time or 
      $logger->logdie("Undefined last_check_time for user $username");
    # check_interval == 1 -> week, 2 -> month
    my $time_interval =  $check_interval==1?604800:2592000;

    if ($current_time - $last_check_time < $time_interval) {
      $current_report->{$username} = $last_user_report;

      $logger->info(sprintf "Less than a %s has passed. SKIP", $check_interval==1?'week':'month');
      next;
    }
  }

  $logger->info("Getting the set of trackDbs for $username");
  my @trackdbs;
  try {
    map { push @trackdbs, Registry::TrackHub::TrackDB->new($_->{_id}) }
      @{$es->search_trackhubs(size => 1000000, query => { term => { owner => $username } })->{hits}{hits}};
  } catch {
    $logger->logdie($_);
  };
  
  $logger->info("User has no trackdbs. SKIP") and next unless scalar @trackdbs;

  # create user specific report
  my $current_user_report = { start_time => time };

  # loop over trackdbs
  #   update doc if the source has changed
  #   check status
  #   format message along the way
  my ($message_body_update, $message_body_problem);
  my $trackdb_update = 0;

  foreach my $trackdb (@trackdbs) {
    $logger->info(sprintf "Checking trackDb [%d]", $trackdb->id);
    my $source = $trackdb->source;
    if ($source) {
      $logger->info(sprintf "trackDb is sourced from UCSC hub.");
      $logger->info("checking remote updates at %s", );
      
      defined $source->{url} and defined $source->{checksum}
	or $logger->logdie("Document source doesn't have url/checksum attributes");

      try {
	# checksum is not enforced in schema, but it must exist once
	# the remote hub JSON has been submitted

	my $checksum = $trackdb->compute_checksum;
       
	if ($checksum and $checksum ne $source->{checksum}) {
	  $logger->info("Remote source has changed, updating.");

	  $trackdb_update = 1;
	  $message_body_update .= sprintf "Detected trackDB [%s] source URL update: ";

	  $logger->info(sprintf "Translating trackDb source to JSON version %s.", $trackdb->version);
	  my $translator = Registry::TrackHub::Translator->new(version => $trackdb->version);
	  my $updated_json_doc = $translator->translate($trackdb->hub->{url}, $trackdb->assembly->{synonyms} || 'unknown')->[0];

	  $logger->info("Validating translated document.");
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

	  $logger->info("Writing document store with updates.");
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
	$logger->warn($_);
	$message_body_update .= "ERROR.\n$@\n";

	# we simply skip update and the status check
	next;
      };
    }
    
    $logger->info("Checking trackDb track status.");
    my $status;
    try {
      $status = $trackdb->update_status();
    } catch {
      $logger->warn($_);

      $message_body_problem .= "Problem updating status for trackDB [%s]\n$@\n\n", $trackdb->id;
      next;
    };
   
    # if problem add trackdb to user report
    if ($status->{tracks}{with_data}{total_ko}) {
      $logger->info("There are faulty tracks, updating report.");
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
  $logger->info("Finished with $username trackDbs.");
  $logger->info("Checking alert report status.");
  
  if ($trackdb_update or scalar keys %{$current_user_report->{ko}}) { # user trackdbs have problems
    # format complete message body
    my $message_body = "This alert report has been automatically generated during the last update of the TrackHub Registry.\n\n";
    $message_body .= $message_body_update . "\n\n" if $message_body_update;
    $message_body .= $message_body_problem;
    
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
    try {
      if ($last_user_report) {
	if ($continuous_alert) {
	  # user wants to be continuously alerted: send message anyway 
	  $logger->info("$username opts for continuous alerts. Sending.");
	  sendmail($message);
	} else {
	  # user doesn't want to be bothered more than once with the same problems
	  # send alert only if current report != last report
	  $logger->info("$username does not opt for continuous alerts. Checking differences with last report.");
	  if ($last_user_report->{ko}) {
	    my @last_report_ko_trackdbs = keys %{$last_user_report->{ko}};
	    my @current_report_ko_trackdbs = keys %{$current_user_report->{ko}};
	    my ($union, $isect, $diff) = 
	      union_intersection_difference(\@current_report_ko_trackdbs, \@last_report_ko_trackdbs);
	  
	    if (scalar @{$diff}) {
	      $logger->info("Detected difference. Sending alert report anyway.");
	      sendmail($message);
	    } else {
	      $logger->info("No difference. Not sending the alert report.");
	    }
	  }
	}
      } else {
	# send alert since this is the first check for this user
	$logger->info("First $username user check. Sending alert report anyway.");
	sendmail($message);
      }
    } catch {
      $logger->logdie($_);
    };
  }

  $logger->info("Adding user report to global report.");
  $current_report->{$username} = $current_user_report;
}
   
$logger->info("Done with users. Storing global report");

my $message_body;
if ($current_report) {
  $current_report->{created} = time;
  my $current_report_id = $last_report_id?++$last_report_id:1;

  try {
    $es->index(index   => $config->{index},
	       type    => $config->{type}{report},
	       id      => $current_report_id,
	       body    => $current_report);
    $es->indices->refresh(index => $config->{index});
  } catch {
    $logger->logdie($_);
  };
  $message_body .= sprintf "Report [%d] has been generated.\n\n", $current_report_id;
  
} else {
  $message_body .= "Report has not been generated.\nReason: no users.\n";
}

$logger->info("Sending alert report to admin.");

my $message = 
  Email::MIME->create(
		      header_str => 
		      [
		       From    => 'admin@trackhubregistry.org',
		       To      => $admin->{email},
		       Subject => sprintf("Alert report from TrackHub Registry: %s", localtime),
		      ],
		      attributes => 
		      {
		       encoding => 'quoted-printable',
		       charset  => 'ISO-8859-1',
		      },
		      body_str => $message_body,
		     );

try {
  sendmail($message);
} catch {
  $logger->logdie($_);
};

$logger->info("DONE.");

__END__

=head1 NAME

update_trackdb_status.pl - Check trackdb tracks and notify its owners

=head1 SYNOPSIS

update_trackdb_status.pl [options]

   -l --logdir          log directory [default: ./trackdb_check_notify]
   -h --help            display this help and exits

=cut
