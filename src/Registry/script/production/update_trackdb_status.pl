#!/usr/bin/env perl
# Copyright [2015-2017] EMBL-European Bioinformatics Institute
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

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
  #$ENV{CATALYST_CONFIG} = "$Bin/../../conf/production/registry.conf"
  $ENV{CATALYST_CONFIG} = "/nfs/public/release/ens_thr/production/src/trackhub-registry/src/Registry/conf/production/registry.hh.conf"
}

use Registry;

use Proc::ProcessTable; # to detect whether the load_public_hubs script's running
use Try::Tiny;
use Log::Log4perl qw(get_logger :levels);
use Getopt::Long;
use Pod::Usage;
use Config::Std;

# use File::Temp qw/ tempfile /;
# use DBM::Deep;
# use Data::Structure::Util qw( unbless );
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;
use Time::HiRes qw(usleep);

use JSON;
use Data::Dumper;

use HTTP::Tiny;
use HTTP::Headers;
use HTTP::Request::Common;
use LWP::UserAgent;

use Search::Elasticsearch;

use Registry::Model::Search;
use Registry::TrackHub::TrackDB;
# use Registry::TrackHub::Translator;
# use Registry::TrackHub::Validator;
use Registry::Utils::Arrays qw( remove_duplicates union_intersection_difference );

my $logger = get_logger();

# default option values
my $help = 0;
#my $log_dir = 'logs';
my $log_dir = '/nfs/public/nobackup/ens_thr/production/trackhub_checks/logs/';
my $type = 'production'; # default cluster type
my $conf_file = '.initrc'; # expect file in current directory

# Initialize SMTP

my $transport = Email::Sender::Transport::SMTP->new({
    host => '193.62.196.50'
});


# parse command-line arguments
my $options_ok =
  GetOptions("config|c=s" => \$conf_file,
	     "logdir|l=s" => \$log_dir,
	     "type|t=s"   => \$type,
	     "help|h"     => \$help) or pod2usage(2);
pod2usage() if $help;

# set up logging, use inline configuration
unless(-d $log_dir) {
  $logger->info("Creating log directory $log_dir");
  mkdir $log_dir or
    $logger->logdie("cannot create directory: $!");
}

my $date = `date '+%F'`; chomp($date);
my $log_file = sprintf "$log_dir/trackhub_check_%s.log", $date;

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

# we've seen duplicates of the automatically managed public hubs are created
# if this script and the load_public_hub.pl are running simultaneously.
# detect if the latter is running and if so suspend execution
my $process_table = Proc::ProcessTable->new->table;
my $is_load_public_hubs_running = grep { $_->{cmndline} =~ /load_public_hubs/ } @{$process_table};
if ($is_load_public_hubs_running) {
  $logger->info("Abort operations as conflicting process is running (load_public_hubs.pl");
  exit;
}

$logger->info("Reading configuration file $conf_file");
my %config;
eval {
  read_config $conf_file => %config
};
$logger->logdie("Error reading configuration file $conf_file: $@") if $@;

my $cluster;
if ($type =~ /prod/) {
  $cluster = 'cluster_prod';
} elsif ($type =~ /stag/) {
  $cluster = 'cluster_staging';
} else {
  $logger->logdie("Unknown type of cluster, should be either 'production' or 'staging'");
}
my $nodes = $config{$cluster}{nodes};

$logger->info("Checking the cluster is up and running");
my $esurl;
if (ref $nodes eq 'ARRAY') {
  $esurl = $nodes->[0];
  $esurl = sprintf "http://%s", $esurl if $esurl !~ /^http/;
} else {
  $esurl = $nodes;
  $esurl = sprintf "http://%s", $esurl if $esurl !~ /^http/;
}
$logger->logdie(sprintf "Cluster %s is not up", $config{$cluster}{name})
  unless HTTP::Tiny->new()->request('GET', $esurl)->{status} eq '200';

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

$logger->info("Getting latest report");
try {
  $last_report = get_latest_report();
  $last_report_id = $last_report->{_id};
  $last_report = $last_report->{_source};
} catch {
  $logger->logdie("Couldn't get latest report:\n$_");
};

$logger->info("Retrieving user lists");
try {
  $users = get_all_users();
  map { $_->{username} =~ /$config{users}{admin_name}/ and $admin = $_ } @{$users};
} catch {
  $logger->logdie("Couldn't get latest user list:\n$_");
};
$admin or $logger->logdie("Unable to find admin user.");

$logger->info("Creating new global report");
my $current_report = {};
$current_report->{created} = time;
my $current_report_id = $last_report_id?++$last_report_id:1;

my $es = Search::Elasticsearch->new(nodes => $nodes);
try {
  $es->index(index   => $config{reports}{alias},
	     type    => $config{reports}{type},
	     id      => $current_report_id,
	     body    => $current_report);
  $es->indices->refresh(index => $config{report}{alias});
} catch {
  $logger->logdie($_);
};

#
# check tracks for every user (except admin)
# spawning a separate process for each user
#
my @children;
foreach my $user (@{$users}) {
  # obviously skip admin user
  my $username = $user->{username};
  next if $username eq $config{users}{admin_name};

  # DEBUG
  # test with just one user
  # next unless $username eq 'uniprot@ebi.ac.uk';
  # next unless $username eq 'avullo';
  # skip Electra as she maintains hundreds of hubs
  # next if $username eq 'mytesting' or $username eq 'testing' or $username eq 'ensemblplants';
  #

  my $pid = fork();
  if ($pid) { # parent
    push(@children, { user => $user->{username}, pid => $pid });
  } elsif ($pid == 0) { # child
    $logger->info("Update global report with user $username info");
    try {
      my $user_report = check_user_tracks($user, $last_report);
      
      # provide partial doc to be merged into the existing report
      $es->update(index   => $config{reports}{alias},
		  type    => $config{reports}{type},
		  id      => $current_report_id,
		  retry_on_conflict => 5,
		  body    => {
			      doc => { $username => $user_report }
			     });
    } catch {
      $logger->logdie($_);
    };
    exit 0;
  } else {
    $logger->logdie("Couldn't fork: $!");
  }
}

foreach my $i (0 .. $#children) {
  my $tmp = waitpid($children[$i]->{pid}, 0);
  usleep(100);

  $logger->info(sprintf "Done with user %s [pid %d]", $children[$i]->{user}, $tmp);
}

# Send message to admin to alert report has/hasn't been generated
my $message_body;
$current_report = $es->get_source(index => $config{reports}{alias},
				  type  => $config{reports}{type},
				  id    => $current_report_id);

if (keys %{$current_report} > 1) {
  $message_body = sprintf "Report [%d] has been generated.\n\n", $current_report_id;
  $message_body .= Dumper $current_report;
  
} else {
  $message_body .= "Report has not been generated.\nReason: no users.\n";
  # delete empty report from index
  $logger->info("Deleting last global report [$current_report_id] from index");
  try {
    $es->delete(index   => $config{reports}{alias},
		type    => $config{reports}{type},
		id      => $current_report_id);
  } catch {
    $logger->logdie($_);
  };
}

$logger->info("Sending alert report to admin");
my $localtime = localtime;
my $message = 
  Email::MIME->create(
		      header_str => 
		      [
		       From    => 'prem@ebi.ac.uk',
		       #To      => $admin->{email},
		       To    => 'avullo@ebi.ac.uk',
                       Cc    => 'prem.apa@gmail.com',
 			Subject => sprintf("Report from TrackHub Registry: %s", $localtime),
		      ],
		      attributes => 
		      {
		       encoding => 'quoted-printable',
		       charset  => 'ISO-8859-1',
		      },
		      body_str => $message_body,
		     );

try {
  sendmail($message, { transport => $transport });
} catch {
  $logger->logdie($_);
};

$logger->info("DONE.");

sub check_user_tracks {
  my ($user, $last_report) = @_;
  defined $user or die "Undefined user";

  my $username = $user->{username};
  defined $username or die "Undefined username";
  $logger->info("Working on user $username");

  # get monitoring configuration
  my $check_interval = $user->{check_interval};
  my $continuous_alert = $user->{continuous_alert};

  # get last report for user
  my $last_user_report = $last_report->{$username};
  my $current_user_report;

  # if check_option is weekly|monthly and (current_time-last_check_time) < week|month
  #   copy last user report to new global report
  #   skip check
  if (defined $last_user_report and $check_interval) { # check_interval == 0 -> 'Automatic' so do the check
    $logger->info(sprintf "%s opts for %s checks. Checking report time interval", $username, $check_interval==1?'weekly':'monthly');
    my $current_time = time;
    my $last_check_time = $last_user_report->{end_time};
    $current_user_report = $last_user_report;

    if (defined $last_check_time) {
      # check_interval == 1 -> week, 2 -> month
      my $time_interval = $check_interval==1?604800:2592000;

      if ($current_time - $last_check_time < $time_interval) {
	$logger->info(sprintf "Less than a %s has passed since last check for %s. SKIP",
		      $check_interval==1?'week':'month', $username);
 
	return $current_user_report;
      }
    } else {
      $logger->error("Undefined last check time in last report for user $username. SKIP");
      return;
    }
  }

  $logger->info("Getting the set of trackDBs for $username");
  my $trackdbs;
  try {
    $trackdbs = get_user_trackdbs($username);
  } catch {
    $logger->error("Unable to get trackDBs for user $username:\n$_");

    return;
  };
  
  $logger->info("User $username has no trackDBs. SKIP") and return
    unless $trackdbs and scalar @{$trackdbs};

  # create user specific report
  $current_user_report = { start_time => time };

  # loop over trackdbs
  #   update doc if the source has changed
  #   check status
  #   format message along the way
  my ($message_body_update, $message_body_problem);
  my $trackdb_update = 0;
  my %updated_trackhubs; # record hubs which have been updated

  foreach my $trackdb (@{$trackdbs}) {
    #
    # WARNING: 
    #   - Can check if trackDB has changed but cannot resubmit as I should know the mapping 
    #     from assembly name to INSDC accession, eventually. This is information which is provided 
    #     by the submitter.
    #   - Also, we should be able to detect a case where the entire structure of the hub might have
    #     changed, with some trackDBs which do not exist any more.
    #
    # my $source = $trackdb->source;
    # if ($source) {
    #   $logger->info(sprintf "trackDb is sourced from UCSC hub.");
    #   $logger->info("checking remote updates at %s", );
      
    #   defined $source->{url} and defined $source->{checksum}
    # 	or $logger->logdie("Document source doesn't have url/checksum attributes");

    #   try {
    # 	# checksum is not enforced in schema, but it must exist once
    # 	# the remote hub JSON has been submitted
    # 	my $checksum = $trackdb->compute_checksum;
    # 	if ($checksum and $checksum ne $source->{checksum}) {
    # 	  $logger->info("Remote source has changed, updating.");

    # 	  $trackdb_update = 1;
    # 	  $message_body_update .= sprintf "Detected trackDB [%s] source URL update, resubmitting to Registry: ";

    # 	  $logger->info(sprintf "Translating trackDb source to JSON version %s.", $trackdb->version);
    # 	  my $translator = Registry::TrackHub::Translator->new(version => $trackdb->version);
    # 	  my $updated_json_doc = $translator->translate($trackdb->hub->{url}, $trackdb->assembly->{synonyms} || 'unknown')->[0];

    # 	  $logger->info("Validating translated document.");
    # 	  my $validator = 
    # 	    Registry::TrackHub::Validator->new(schema => Registry->config()->{TrackHub}{schema}{$trackdb->version});
    # 	  my ($fh, $filename) = tempfile( DIR => '.', SUFFIX => '.json', UNLINK => 1); print $fh $updated_json_doc; close $fh;
    # 	  $validator->validate($filename);

    # 	  my $updated_doc = from_json($updated_json_doc);

    # 	  # TODO? Prevent submission of duplicate content
    # 	  # i.e. trackdb with same hub/assembly
    # 	  # it shouldn't be the case
	  
    # 	  # set the owner/created/updated/status/source attributes
    # 	  $updated_doc->{owner} = $username;
    # 	  $updated_doc->{created} = $trackdb->created;
    # 	  $updated_doc->{updated} = time;
    # 	  $updated_doc->{status}{message} = 'Unknown';
    # 	  $updated_doc->{source}{checksum} = $checksum;

    # 	  $logger->info("Writing document store with updates.");
    # 	  $es->index(index   => $config->{trackhub}{index},
    # 		     type    => $config->{trackhub}{type},
    # 		     id      => $trackdb->id,
    # 		     body    => $updated_doc);
    # 	  $es->indices->refresh(index => $config->{trackhub}{index});

    # 	  # re-instantiate the trackdb since the document has changed
    # 	  $trackdb = Registry::TrackHub::TrackDB->new($trackdb->id);

    # 	  $message_body_update .= "SUCCESS.\n\n";
    # 	}
    #   } catch {
    # 	$logger->warn($_);
    # 	$message_body_update .= "ERROR.\n$@\n";

    # 	# we simply skip update and the status check
    # 	next;
    #   };
    # }

    my ($id, $hub, $assembly) = ($trackdb->id, $trackdb->hub->{name}, $trackdb->assembly->{name});
    $logger->info(sprintf "User: %s. Checking trackDB [%s] (hub: %s, assembly: %s)", $username, $id, $hub, $assembly);
    my $status;
    try {
      $status = $trackdb->update_status();
    } catch {
      $logger->error("Could not update status for trackDB [$id]:\n$_");

      $message_body_problem .= 
	sprintf "Problem updating status for trackDB [%s] (hub: %s, assembly: %s)\n$@\n\n", 
	  $id, $hub, $assembly;
      return;
    };
   
    # if problem, it might be a temporary one, retry a few times before reporting the fault
    if ($status->{tracks}{with_data}{total_ko}) {
      $logger->info("There are faulty tracks, retrying in case of temporary problem");
      for (1 .. 5) {
	$logger->info("Retrying ($_)");
	try {
	  $status = $trackdb->update_status();
	  $logger->info("Previously detected faulty tracks seem to be ok now, abort retrying") and last
	    unless $status->{tracks}{with_data}{total_ko};
	} catch {
	  $logger->error("Could not update status for trackDB [$id]:\n$_");

	  $message_body_problem .= 
	    sprintf "Problem updating status for trackDB [%s] (hub: %s, assembly: %s)\n$@\n\n", 
	    $id, $hub, $assembly;
	  return;
	};
      }
    }
    
    # if problem add trackdb to user report
    if ($status->{tracks}{with_data}{total_ko}) {
      $logger->info("There are faulty tracks, updating report.");
      $current_user_report->{ko}{$id} =
	$status->{tracks}{with_data}{ko};

      $message_body_problem .= sprintf "trackDB [%s] (hub: %s, assembly: %s)\n", $id, $hub, $assembly;
      foreach my $track (keys %{$current_user_report->{ko}{$id}}) {
	$message_body_problem .= sprintf "\t%s\t%s\t%s\n", $track, $current_user_report->{ko}{$id}{$track}[0], $current_user_report->{ko}{$id}{$track}[1];
      }
      $message_body_problem .= "\n\n";
    } else {
      push @{$current_user_report->{ok}}, $id;
    }
  }
  $current_user_report->{end_time} = time;
  $logger->info("Finished with $username trackDBs.");

  $logger->info("Checking alert report status.");  
  if (scalar keys %{$current_user_report->{ko}}) { # user trackdbs have problems
    # format complete message body
    my $user_message_body = "This alert report has been automatically generated during the last update of the TrackHub Registry.\n\n";
    # $user_message_body .= $message_body_update . "\n\n" if $message_body_update;
    $user_message_body .= $message_body_problem;
    $user_message_body .= "\n\nYou can view a report for each of the above trackDBs by logging into the Trackhub Registry web front end (http://www.trackhubregistry.org/login).\n\n";
    $user_message_body .= "The Registry has disabled the links of these hubs to various genome browsers. Do please fix the problems so that next time the Registry checks the hubs\n";
    $user_message_body .= "it will be able to restore the links.\n";
    $user_message_body .= "Regards,\n\nThe Trackhub Registry team\n";
    
    my $message = 
      Email::MIME->create(
			  header_str => 
			  [
			   From    => 'prem@ebi.ac.uk',
			   #To      => $user->{email},
			   To      => 'avullo@ebi.ac.uk',
			   Cc     => 'prem.apa@gmail.com',
			   Subject => sprintf "Trackhub Registry: Alert Report for user [%s]", $username,
			  ],
			  attributes => 
			  {
			   encoding => 'quoted-printable',
			   charset  => 'ISO-8859-1',
			  },
			  body_str => $user_message_body,
			 );

    # check whether we have to send an alert to the user and send it, eventually
    try {
      if ($continuous_alert) {
	# user wants to be continuously alerted: send message anyway 
	$logger->info("$username opts for continuous alerts. Sending report.");
	sendmail($message, { transport => $transport });
      } elsif ($last_user_report) {
	# user doesn't want to be bothered more than once with the same problems
	# send alert only if current report != last report
	$logger->info("$username does not opt for continuous alerts. Checking differences with last report");
	if ($last_user_report->{ko}) {
	  my @last_report_ko_trackdbs = keys %{$last_user_report->{ko}};
	  my @current_report_ko_trackdbs = keys %{$current_user_report->{ko}};
	  my ($union, $isect, $diff) = 
	    union_intersection_difference(\@current_report_ko_trackdbs, \@last_report_ko_trackdbs);
	  
	  if (scalar @{$diff}) {
	    $logger->info("[$username]. Detected difference: sending alert report anyway.");
	    sendmail($message, { transport => $transport });
	  } else {
	    $logger->info("[$username]. No differences: not sending the alert report.");
	  }
	} else {
	  # should send since we have problems in the new run
	  $logger->info("[$username]. Last run there wasn't any problem, but now there is. Sending alert report");
	  sendmail($message, { transport => $transport });
	}
      } else {
	# send alert since this is the first check for this user
	$logger->info("First $username user check. Sending alert report anyway");
	sendmail($message, { transport => $transport });
      }
    } catch {
      $logger->error($_);
    };
  }

  return $current_user_report;
}
  
sub get_all_users {
  my ($index, $type) = ($config{users}{alias}, $config{users}{type});
  my $nodes = $config{$cluster}{nodes};
  defined $index or die "Couldn't find index for users in configuration file";
  defined $type or die "Couldn't find type for users in configuration file";
  defined $nodes or die "Couldn't find ES nodes in configuration file";

  my $es = Search::Elasticsearch->new(nodes => $nodes);

  # use scan & scroll API
  # see https://metacpan.org/pod/Search::Elasticsearch::Scroll
  my $scroll = $es->scroll_helper(index => $index, type  => $type);
  my @users;
  while (my $user = $scroll->next) {
    push @users, $user->{_source};
  }

  return \@users;
}

sub get_latest_report {
  my ($index, $type) = ($config{reports}{alias}, $config{reports}{type});
  my $nodes = $config{$cluster}{nodes};
  defined $index or die "Couldn't find index for reports in configuration file";
  defined $type or die "Couldn't find type for reports in configuration file";
  defined $nodes or die "Couldn't find ES nodes in configuration file";

  my %args = 
    (
     index => $index,
     type  => $type,
     size  => 1,
     body  => 
     {
      sort => [ 
	       { 
		created => {
			    order => 'desc',
			    # would otherwise throw exception if there
			    # are documents missing the field,
			    # see http://stackoverflow.com/questions/17051709/no-mapping-found-for-field-in-order-to-sort-on-in-elasticsearch
			    # TODO:
			    # Before 1.4.0 there was the ignore_unmapped boolean parameter, which was not enough information to 
			    # decide on the sort values to emit, and didn’t work for cross-index search. It is still supported 
			    # but users are encouraged to migrate to the new unmapped_type instead.
			    # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-request-sort.html
			    ignore_unmapped => 'true' 
			   }
	       }
	      ]
     }
    );

  my $es = Search::Elasticsearch->new(nodes => $nodes);
  
  return $es->search(%args)->{hits}{hits}[0];
}

sub get_user_trackdbs {
  my $user = shift;
  defined $user or die "Undefined username";

  my ($index, $type) = ($config{trackhubs}{alias}, $config{trackhubs}{type});
  my $nodes = $config{$cluster}{nodes};
  defined $index or die "Couldn't find index for users in configuration file";
  defined $type or die "Couldn't find type for users in configuration file";
  defined $nodes or die "Couldn't find ES nodes in configuration file";

  my $es = Search::Elasticsearch->new(nodes => $nodes);
  
  # my $scroll = $es->scroll_helper(index => $index,
  # 				  type  => $type,
  # 				  search_type => 'scan',
  # 				  body  => { query => { term => { owner => $user } } });

  # my $trackdbs;
  # while (my $trackdb = $scroll->next) {
  #   push @{$trackdbs}, Registry::TrackHub::TrackDB->new($trackdb->{_id});
  # }

  my $trackdbs;
  map { push @{$trackdbs}, Registry::TrackHub::TrackDB->new($_->{_id}) }
    @{$es->search(index => $index,
		  type  => $type,
		  size  => 100000,
		  body  => { query => { term => { owner => $user } }, fields => [] })->{hits}{hits}};

  return $trackdbs;
}

__END__

=head1 NAME

update_trackdb_status.pl - Check trackdb tracks and notify its owners

=head1 SYNOPSIS

update_trackdb_status.pl [options]

   -c --config          configuration file [default: .initrc]
   -l --logdir          log directory [default: ./.logs]
   -t --type            cluster type (production, staging) [default: production]
   -h --help            display this help and exits

=cut
