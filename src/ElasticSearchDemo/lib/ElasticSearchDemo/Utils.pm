package ElasticSearchDemo::Utils;

use strict;
use warnings;

use LWP;

#
# TODO
# Have to use this until I implement with Moose
#
BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/..";
}

sub slurp_file {
  my $file = shift;
  defined $file or die "Undefined file";

  my $string;
  {
    local $/=undef;
    open FILE, "<$file" or die "Couldn't open file: $!";
    $string = <FILE>;
    close FILE;
  }
  
  return $string;
}

sub es_running {
  return _get('http://localhost:9200')->is_success;
}

sub _get {
  my ($href) = @_;

  my $req = HTTP::Request->new( GET => $href );

  my $ua = LWP::UserAgent->new;
  my $response = $ua->request($req);

  return $response;
}

1;
