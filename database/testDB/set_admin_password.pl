#!/usr/bin/env perl
 
use strict;
use warnings;
use lib 'lib';
 
BEGIN { $ENV{CATALYST_DEBUG} = 0 }
 
use Registry;
use DateTime;


my $schema = Registry::Schema->connect('dbi:SQLite:registry.db');
    
my @users = $schema->resultset('User')->all;
    
foreach my $user (@users) {
       $user->update({ password => $user->{"_column_data"}->{"password"} });
}
 

