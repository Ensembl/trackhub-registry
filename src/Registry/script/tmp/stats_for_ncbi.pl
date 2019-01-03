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
use Data::Dumper;

local $SIG{__WARN__} = sub {};

use JSON;
use HTTP::Headers;
use HTTP::Request::Common;
use LWP::UserAgent;
use Data::Dumper;

$| = 1;
my $ua = LWP::UserAgent->new;
my $server = 'https://beta.trackhubregistry.org';

# my ($user, $pass) = ($ARGV[0], $ARGV[1]); 
# my $request = GET("$server/api/login");
# $request->headers->authorization_basic($user, $pass);
# my $response = $ua->request($request);
# my $auth_token;
# if ($response->is_success) {
#   $auth_token = from_json($response->content)->{auth_token};
#   print "Logged in [$auth_token]\n" if $auth_token;
# } else {
#   die sprintf "Couldn't login: %s [%d]", $response->content, $response->code;
# }

my $request = GET("$server/api/info/trackhubs");
my $response = $ua->request($request);

my %format_lookup = (
 'bed'    => 'BED',
 'bb'     => 'BigBed',
 'bigBed' => 'BigBed',
 'bw'     => 'BigWig',
 'bigWig' => 'BigWig',
 'bam'    => 'BAM',
 'gz'     => 'VCFTabix',
 'cram'   => 'CRAM'
);

my $stats;
if ($response->code == 200) {
  my $hubs = from_json($response->content);
  # print Dumper $hubs;

  foreach my $hub (@{$hubs}) {
    foreach my $trackdb (@{$hub->{trackdbs}}) {
      my $uri = $trackdb->{uri};
      next unless $uri;
      
      $request = GET($uri);
      $response = $ua->request($request);
      if ($response->code == 200) {
        my $trackdb = from_json($response->content);
        my $file_type = {};
        _collect_track_info($trackdb->{configuration}, $file_type);
        $stats->{$hub->{name}} = $file_type;
      } else {
        print STDERR "Couldn't get trackdb: %s [%d]", $response->content, $response->code;
      }
    }
  }
} else {
  print STDERR "Couldn't get list of trackhubs: %s [%d]", $response->content, $response->code;
}

# print Dumper $stats;

my %file_types;
grep { $file_types{$_}++ } values %format_lookup;
my @file_types = sort keys %file_types;
print "Hub\t"; map { print "$_\t" } @file_types;
print "\n";
foreach my $hub (keys %{$stats}) {
  print "$hub\t";
  foreach my $type (@file_types) {
    my $type_value = 0;
    $type_value = $stats->{$hub}{$type} if exists $stats->{$hub}{$type};
    print "$type_value\t";
  }
  print "\n";
}

# Logout 
# $request = GET("$server/api/logout");
# $request->headers->header(user       => $user);
# $request->headers->header(auth_token => $auth_token);
# if ($response->is_success) {
#   print "Logged out\n";
# } else {
#   print "Unable to logout\n";
# } 

sub _collect_track_info {
  my ($hash, $file_type) = @_;
  foreach my $track (keys %{$hash}) { # key is track name

    if (ref $hash->{$track} eq 'HASH') {
      foreach my $attr (keys %{$hash->{$track}}) {
        next unless $attr =~ /bigdataurl/i or $attr eq 'members';
        if ($attr eq 'members') {
          _collect_track_info($hash->{$track}{$attr}, $file_type) if ref $hash->{$track}{$attr} eq 'HASH';
        } else {

          # determine type
          my $url = $hash->{$track}{$attr};
          my @path = split(/\./, $url);
          my $index = -1;
          # # handle compressed formats
          # $index = -2 if $path[-1] eq 'gz';
          $file_type->{$format_lookup{$path[$index]}}++;
        }

      }
    }
  } 
}
