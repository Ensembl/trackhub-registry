#!/usr/bin/env perl

#Use this script to dump user info in to sqlite3 database
use strict;
use warnings;
use lib 'lib';

BEGIN { $ENV{CATALYST_DEBUG} = 0 }

use JSON;
use DBI;

# Step1: Read json dump and store it in a data structure
my $json;

open my $fh, "<", "../prod_elastic_dumps/users_v1_data.json";
use Data::Dumper;

my $user_info = {};
my $counter   = 0;
while (<$fh>) {

	my $data = decode_json($_);

	#print STDERR Dumper($data);
	$user_info->{ $data->{_id} } = $data->{_source};
	$counter++;
}
print "Number of users $counter\n";
print "NUmer of keys in hash ", scalar( keys $user_info ), "\n";

# Step2: Create the schema
system("sqlite3 registry.db < registry_userdb_schema.sql");

# Step3: Load the user into to sqlite3 db

#
my $dbfile = "registry.db";

my $dsn      = "dbi:SQLite:dbname=$dbfile";
my $user     = "";
my $password = "";
my $dbh      = DBI->connect(
	$dsn, $user,
	$password,
	{
		PrintError => 0,
		RaiseError => 1,
		AutoCommit => 1,
	}
);

# prepare statements
my $sth_user = $dbh->prepare(
"INSERT INTO users (username, password, first_name, last_name, email_address, affiliation,continuous_alert, check_interval) VALUES (?,?,?,?,?,?,?,?)"
);

my $sth_user_roles = $dbh->prepare(
"INSERT INTO user_roles (user_id, role_id) VALUES (?, ?)"
);


my ($admin_role_id) = $dbh->selectrow_array("SELECT id FROM roles WHERE name = 'admin'");
my ($user_role_id) = $dbh->selectrow_array("SELECT id FROM roles WHERE  name = 'user'");

while ( my ( $id, $current_user ) = each %$user_info ) {

    $current_user->{continuous_alert} = scalar($current_user->{continuous_alert}) < 1 ? 0 : $current_user->{continuous_alert};
    $current_user->{check_interval} = scalar($current_user->{check_interval}) < 1 ? 0 : $current_user->{check_interval};
	$sth_user->execute(
		$current_user->{username},         $current_user->{password},
		$current_user->{first_name},       $current_user->{last_name},
		$current_user->{email},    $current_user->{affiliation},
		$current_user->{continuous_alert}, $current_user->{check_interval},
	);
	print STDERR "Inserted user ", $current_user->{username}, "\n";
	#insert user roles
	my ($current_user_id) = $dbh->selectrow_array("SELECT id FROM users WHERE username = '". $current_user->{username} . "'");
	my $roles = $current_user->{roles};
	foreach my $role(@$roles){
		my ($user_role_id) = $dbh->selectrow_array("SELECT id FROM roles WHERE  name = '" . $role . "'");
		$sth_user_roles->execute($current_user_id, $user_role_id);
	}
}

$dbh->disconnect;


use Registry;
use DateTime;

my $schema = Registry::Schema->connect('dbi:SQLite:registry.db');

my @users = $schema->resultset('User')->all;

foreach my $user (@users) {
       $user->update({ password => $user->{"_column_data"}->{"password"} });
}


