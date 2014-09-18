#!/usr/bin/env perl

use strict;
use warnings;

use JSON;
use JSON::Schema;
use Data::Dumper;

my ($schema_file, $json_file) = @ARGV;

my ($schema_string, $json_string) = 
  (&slurp_file($schema_file), &slurp_file($json_file));

my $validator = JSON::Schema->new($schema_string); #, %options);
my $json      = from_json($json_string);
my $result    = $validator->validate($json);
 
if ($result) {
  print "Valid!\n";
} else {
  print "Errors\n";
  print " - $_\n" foreach $result->errors;
}

sub slurp_file {
  my $file = shift;

  my $string;
  {
    local $/=undef;
    open FILE, "<$file" or die "Couldn't open file: $!";
    $string = <FILE>;
    close FILE;
  }
  
  return $string;
}
