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

use Registry::User::DB;
use Getopt::Long;
use Pod::Usage;
use Digest;

my ($dsn, $db_user, $db_pass, $adm_user, $adm_pass, $help, $driver, $salt);

GetOptions (
  'dsn=s'       => \$dsn,
  'db_user=s'   => \$db_user,
  'db_pass=s'   => \$db_pass,
  'adm_user=s'  => \$adm_user,
  'adm_pass=s'  => \$adm_pass,
  'driver=s'    => \$driver,
  'salt=s'      => \$salt,
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

# Create some roles if they're not there.

$orm->schema->resultset('Role')->find_or_create({
  name => 'user'
});
$orm->schema->resultset('Role')->find_or_create({
  name => 'admin'
});


my $digest = Digest->new('SHA-256');
$digest->add($salt);
$digest->add($adm_pass);

my $admin_user = $orm->schema->resultset('User')->create({
  username => $adm_user,
  first_name => 'Admin',
  password => $digest->b64digest,
  affiliation => 'EMBL-EBI',
  email => 'ens-apps@ebi.ac.uk',
  continuous_alert => 0
});

$admin_user->add_to_roles({ name => 'user' });
$admin_user->add_to_roles({ name => 'admin' });

=head1 NAME

deploy_user_account_system.pl - Creates an SQL database for Trackhub Registry user accounts. Requires a DB host with a RW user

=head1 SYNOPSIS

deploy_user_account_system.pl --dsn ... [--db_user, --db_pass] --adm_user [] --adm_pass [] --driver ...

  --dsn       Database host connection params (required)
              e.g. dbi:mysql:database=thr_user;host=sql.com;port=3306 
                   dbi:sqlite:database=thr_user.db
  --db_user   RW user for database host (needed for MySQL driver)
  --db_pass   RW user password (needed for MySQL driver)
  --adm_user  User name for web admin user (required, not DB admin)
  --adm_pass  Password for web admin user (required, not DB admin)
  --driver    Database engine mysql | SQLite
  --salt      Password salt as used in the server config
  -h --help   display this help and exit

=cut