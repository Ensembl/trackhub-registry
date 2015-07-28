package Registry::Utils;

use strict;
use warnings;

use LWP;
use HTTP::Tiny;
use File::Temp qw/ tempfile /;
use Digest::MD5 qw(md5_hex);
use Registry::Utils::URL qw(read_file);

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

# compute checksum for file at a remote URL
sub checksum_compute {
  my $url = shift;
  
  my $response = read_file($url, { nice => 1 });
  my $content;
 
  if ($response->{error}) {
    push @{$response->{error}}, "Please the check the source URL in a web browser.";
    die join("\n", @{$response->{error}});
  }
  $content = $response->{'content'};

  # my ($fh, $filename) = tempfile( DIR => '.', UNLINK => 1);
  # print $fh $content;
  # close $fh;

  # my $cmd = sprintf("md5sum %s | cut -d ' ' -f 1", $filename);
  # my ($rc, $output) = run_cmd($cmd);

  # $output =~ s/^\s+|\s+$|\n//g; # trim left/right spaces and newlines
  # return $output;

  return md5_hex($content);
}

# Runs the given command and returns a list of exit code and output
sub run_cmd {
  my $cmd = shift;
  my $output = `$cmd 2>&1`;
  my $rc = $? >> 8;

  # my ($rc, $output);
  # open CMD, '-|', $cmd;
  # my $line;
  # while (defined($line=<CMD>)) {
  #   $output .= $line;
  # }
  # close CMD;

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
