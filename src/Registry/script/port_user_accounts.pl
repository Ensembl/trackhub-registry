#!/usr/bin/env perl
# Copyright [2015-2022] EMBL-European Bioinformatics Institute
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

use Registry::User::DB;
use Getopt::Long;
use Pod::Usage;
use Digest;
use Search::Elasticsearch;

my ($dsn, $db_user, $db_pass, $adm_user, $adm_pass, $help, $driver, $salt, $es_host, $es_port, $es_index);

GetOptions (
  'dsn=s'       => \$dsn,
  'db_user=s'   => \$db_user,
  'db_pass=s'   => \$db_pass,
  'adm_user=s'  => \$adm_user,
  'adm_pass=s'  => \$adm_pass,
  'driver=s'    => \$driver,
  'salt=s'      => \$salt,
  'es_host=s'   => \$es_host,
  'es_port=s'   => \$es_port,
  'es_index=s'  => \$es_index,
  'help|h'      => \$help,
) or pod2usage(2);

pod2usage() if $help;


my $orm = Registry::User::DB->new(
  dsn => $dsn,
  config => {
    dbuser => $db_user,
    dbpass => $db_pass,
    create => 1,
    driver => $driver
  }
);
$orm->schema->resultset('User')->find({
  username => '*'
}); # Poke the DB to ensure functionality

my $es_client = Search::Elasticsearch->new(
  nodes => $es_host.':'.$es_port
);

my $scroll = $es_client->scroll_helper(
  index => $es_index,
  body => {
    query => { match_all => {} },
    size => 1000
  }
);
my $ported = 0;
while (my $response = $scroll->next) {
  my $user = $response->{_source};
  
  my $digest = Digest->new('SHA-256');
  $digest->add($salt);
  $digest->add($user->{password});
  my $encoded_password = $digest->b64digest;

  my $transferred_user = $orm->schema->resultset('User')->create({
    username => $user->{username},
    first_name => $user->{first_name},
    last_name => $user->{last_name},
    email => $user->{email},
    password => $encoded_password,
    affiliation => $user->{affiliation},
    check_interval => $user->{check_interval},
    continuous_alert => $user->{continuous_alert} // 0,
  });

  $transferred_user->add_to_roles({ name => 'user'});
  $ported++;
  printf "Added %d: %s\n",$ported,$user->{username};
}

=head1 NAME

port_user_accounts.pl - Copies users out of Elasticsearch, and recreates them in an RDBMS. Note: You will have to delete the user account yourself

=head1 SYNOPSIS

port_user_accounts.pl --dsn .. [--db_user, --db_pass] --adm_user $ --adm_pass $ --driver $ --es_host $ --es_port $ --es_index $

  --dsn       Database host connection params (required)
              e.g. dbi:mysql:database=thr_user;host=sql.com;port=3306 
                   dbi:sqlite:database=thr_user.db
  --db_user   RW user for database host (needed for MySQL driver)
  --db_pass   RW user password (needed for MySQL driver)
  --adm_user  User name for web admin user (required, not DB admin)
  --adm_pass  Password for web admin user (required, not DB admin)
  --driver    Database engine mysql | SQLite
  --salt      Password salt as used in the server config
  --es_host   Host running THR Elasticsearch
  --es_port   Port of THR Elasticsearch
  --es_index  The index name for the users in Elasticsearch
  -h --help   display this help and exit

=cut