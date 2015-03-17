package Registry::Utils;

use strict;
use warnings;

use LWP;
use HTTP::Tiny;

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

# Runs the given command and returns a list of exit code and output
sub run_cmd {
  my ($self, $cmd) = @_;
  my $output = `$cmd 2>&1`;
  my $rc = $? >> 8;
  die "Cannot run program '$cmd'. Return code was ${rc}. Program output was $output" if $rc;
  return ($rc, $output);
}

sub internet_connection_ok {
  #
  # For some reason, Net::Ping doeesn't reach the host
  # even if the connection is ok and ping works
  # on the command line
  #
  # my $p = Net::Ping->new();
  # my $ok = $p->ping("www.google.com", 5);
  # $p->close();
  # return $ok;
  
  return HTTP::Tiny->new()->request('GET', "http://www.google.com")->{success};
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
