#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2018] EMBL-European Bioinformatics Institute
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
use Daemon::Control;
use FindBin qw($Bin);

my $root_dir   = $ENV{THR_ROOT} || "$Bin/../../";
my $psgi_file  = "$root_dir/conf/production/registry.psgi";
my $container  = $ENV{THR_STARMAN} || 'starman';
my $port       = $ENV{THR_PORT} || 5000;
my $workers    = $ENV{THR_WORKERS} || 5;
my $backlog    = $ENV{THR_BACKLOG} || 1024;
my $status_file= $ENV{THR_STATUS} || "$root_dir/trackhub_registry.status";
my $restart_interval = 1;
my $max_requests=$ENV{THR_MAX_REQUESTS} || 10000;

my $log_dir = $ENV{THR_LOG_DIR} || "$root_dir/logs/";
#my $access_log = Disabled for GDPR reasons
my $error_log  = $log_dir."/$ENV{HOSTNAME}.error.log";
my $pid_file   = $ENV{THR_PID} || "$root_dir/trackhub_registry.pid";
my $init_config= $ENV{THR_CONFIG} || '~/.bashrc';

print "Starting server with config:\n";
printf "Application root\t%s\nPSGI config\t%s\nEnvironment\t$init_config\n",$root_dir,$psgi_file,$init_config;
printf "Server port\t%s\nServer status\t%s\nLog location\t%s\nPID\t%s\n",$port,$status_file,$log_dir,$pid_file;
printf "Server error log\t %s\n",$error_log;

Daemon::Control->new(
  {
    name         => "Trackhub Registry",
    lsb_start    => '$syslog $remote_fs',
    lsb_stop     => '$syslog',
    lsb_sdesc    => 'Trackhub Registry server control',
    lsb_desc     => 'Trackhub Registry server control',
    stop_signals => [ qw(QUIT TERM TERM INT KILL) ],
    init_config  => $init_config,
    program      => $container,
    program_args => [
      '--backlog',    $backlog,
      '--listen',     ":$port",
      '--workers',    $workers,
      '--max-requests',$max_requests,
      '--status-file', $status_file,
      '--interval',   $restart_interval,
      '--error-log', $error_log,
      $psgi_file
    ],
    pid_file     => $pid_file,
  }
)->run;
