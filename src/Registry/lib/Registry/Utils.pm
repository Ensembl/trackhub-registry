=head1 LICENSE

Copyright [2015-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

Please email comments or questions to the Trackhub Registry help desk
at C<< <http://www.trackhubregistry.org/help> >>

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::Utils - Useful methods

=head1 SYNOPSIS

  # get file content into a scalar
  my $file_contents = slurp('/my/file/location.txt');
  print length($file_contents);

=head1 DESCRIPTION

A collections of useful functions

=cut

package Registry::Utils;

use strict;
use warnings;

use LWP;
use HTTP::Tiny;
use File::Temp qw/ tempfile /;
use Digest::MD5 qw(md5_hex);
use Registry::Utils::URL qw(read_file);

=head1 FUNCTIONS

=head2 slurp_file

  Arg [1]     : string $file
  Description : Forces the contents of a file into a scalar. This is the 
                fastest way to get a file into memory in Perl. 
  Returntype  : Scalar 
  Example     : my $contents = slurp('/tmp/file.txt');
  Exceptions  : If the file did not exist or was not readable
  Status      : stable

=cut

sub slurp_file {
  my $file = shift;
  defined $file or die "Undefined file";

  my $string;
  {
    local $/=undef;
    open my $fh, "$file", 'r' or die "Couldn't open file: $!";
    $string = <$fh>;
    close $fh;
  }
  
  return $string;
}

=head2 checksum_compute

  Arg [1]     : string $url
  Description : Compute checksum for a file at a given remote URL.
                Returned checksum is MD5 Hex
  Returntype  : Scalar 
  Example     : my $chksum = compute_checksum('ftp:///tmp/file.txt');
  Exceptions  : If the file did not exist or was not readable
  Status      : stable

=cut

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

=head2 run_cmd

  Arg [1]     : string $command
  Description : Runs the given command and returns a list of exit code and output
  Returntype  : Array ($returned_code, $output)
  Example     : my ($rc, $output) = run_cmd('ls');
  Exceptions  : none
  Status      : stable

=cut

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

=head2 internet_connection_ok

  Arg [1]     : none
  Description : Check whether host is connected to Internet
  Returntype  : Scalar
  Example     : my $ok = internet_connection_ok();
  Exceptions  : none
  Status      : stable

=cut

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

=head2 es_running

  Arg [1]     : none
  Description : Check whether an Elasticsearch instance is running on localhost
                and is listening to the default port (9200)
  Returntype  : Scalar
  Example     : my $ok = internet_connection_ok();
  Exceptions  : none
  Status      : stable

=cut

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
