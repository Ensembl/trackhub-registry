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

=head1 NAME

Registry::Utils::URL - URL utilities

=head1 SYNOPSIS

warn "Cannot reach file" unless file_exists("ftp://ftp.somedomain.org/pub/README");
my $readme_content = file_read("ftp://ftp.somedomain.org/pub/README");

=head1 DESCRIPTION

File access methods have two modes: "nice" mode is most suitable for
web interfaces, and returns a hashref containing either the raw content
or a user-friendly error message (no exceptions are thrown). "Non-nice" 
or raw mode returns 0/1 for failure/success or the expected raw data, 
and optionally throws exceptions.

NOTE: this functions are borrowed from the Ensembl web team code base.

=cut

package Registry::Utils::URL;


use strict;
use warnings;

use HTTP::Tiny;
use LWP::UserAgent;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../..";
}

use Registry::Utils::File qw(get_compression);

use Exporter qw(import);
our @EXPORT_OK = qw(chase_redirects file_exists read_file get_filesize);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

=head1 METHODS

=head2 chase_redirects

  Arg [1]     : String - path to file | EnsEMBL::Web::File object
  Arg [2]     : HashRef - 
                         proxy (optional) String
                         max_follow (optional) Integer - maximum number of redirects to follow
  Example     : my $url = chase_redirects(""ftp://ftp.somedomain.org/pub/README");
  Description : Deal with files "hidden" behind a URL-shortening service such as tinyurl
  Returntype  : url (String) or Hashref containing errors (ArrayRef)
  Caller      : General
  Status      : Stable

=cut

sub chase_redirects {
  my ($file, $args) = @_;
  my $url = $file;

  $args->{'max_follow'} = 10 unless defined $args->{'max_follow'};

  if ($url =~ /^ftp/) {
    my $ua = LWP::UserAgent->new( max_redirect => $args->{'max_follow'} );
    $ua->timeout(10);
    $ua->env_proxy;
    $ua->proxy([qw(http https)], $args->{'proxy'}) || ();
    my $response = $ua->head($url);
    return $response->is_success
      ? $response->request->uri->as_string : {'error' => [_get_lwp_useragent_error($response)]};
  }
  else {
    my %args = (
      'timeout'       => 10,
      'max_redirect'  => $args->{'max_follow'},
    );
    if ($args->{'proxy'}) {
      $args{'http_proxy'}   = $args->{'proxy'};
      $args{'https_proxy'}  = $args->{'proxy'};
    }
    my $http = HTTP::Tiny->new(%args);

    my $response = $http->request('HEAD', $url);
    if ($response->{'success'}) {
      return $response->{'url'};
    }
    else {
      return {'error' => [_get_http_tiny_error($response)]};
    }
  }
}

=head2 file_exists

  Arg [1]     : File - EnsEMBL::Web::File object or path to file (String)
  Arg [2]     : HashRef - 
                         proxy (optional) String
                         nice (optional) Boolean - see introduction
                         no_exception (optional) Boolean             
  Example     : my $exists = file_exists(""ftp://ftp.somedomain.org/pub/README");
  Description : Check if a file of this name exists
  Returntype  : Hashref (nice mode) or Boolean 
  Caller      : General
  Status      : Stable

=cut

sub file_exists {
### 
### @param Args Hashref 
### @param proxy      (optional) String
###                  
### @return Hashref (nice mode) or Boolean 
  my ($file, $args) = @_;
  my $url = $file;

  my ($success, $error);

  if ($url =~ /^ftp/) {
    my $ua = LWP::UserAgent->new();
    $ua->timeout(10);
    $ua->env_proxy;
    $ua->proxy([qw(http https)], $args->{'proxy'}) || ();
    my $response = $ua->head($url);
    unless ($response->is_success) {
      $error = _get_lwp_useragent_error($response);
    }
  }
  else {
    my %params = ('timeout'       => 10);
    if ($args->{'proxy'}) {
      $params{'http_proxy'}   = $args->{'proxy'};
      $params{'https_proxy'}  = $args->{'proxy'};
    }
    my $http = HTTP::Tiny->new(%params);

    my $response = $http->request('HEAD', $url);
    unless ($response->{'success'}) {
      $error = _get_http_tiny_error($response);
    }
  }

  if ($args->{'nice'}) {
    return $error ? {'error' => [$error]} : {'success' => 1};
  }
  else {
    if ($error) {
      die "File $url could not be found: $error" unless $args->{'no_exception'};
      return 0;
    }
    else {
      return 1;
    }
  }
}

=head2 read_file

  Arg [1]     : File - EnsEMBL::Web::File object or path to file (String)
  Arg [2]     : HashRef - 
                         proxy (optional) String
                         nice (optional) Boolean - see introduction
                         compression (optional) String - see introduction
  Example     : my $content = read_file(""ftp://ftp.somedomain.org/pub/README");
  Description : Get entire content of file
  Returntype  : Hashref (in nice mode) or String - contents of file
  Caller      : General
  Status      : Stable

=cut

sub read_file {
  my ($file, $args) = @_;
  my $url = $file;

  my ($content, $error);

  if ($url =~ /^ftp/) {
    my $ua = LWP::UserAgent->new();
    $ua->timeout(10);
    $ua->env_proxy;
    $ua->proxy([qw(http https)], $args->{'proxy'}) || ();
    my $response = $ua->get($url);
    if ($response->is_success) {
      $content = $response->content;
    }
    else {
      $error = _get_lwp_useragent_error($response);
    }
  }
  else {
    my %params = ('timeout' => 30);
    if ($args->{'proxy'}) {
      $params{'http_proxy'}   = $args->{'proxy'};
      $params{'https_proxy'}  = $args->{'proxy'};
    }
    my $http = HTTP::Tiny->new(%params);

    my $response = $http->request('GET', $url);
    if ($response->{'success'}) {
      $content = $response->{'content'};
    }
    else {
      warn "!!! ERROR FETCHING FILE $url";
      $error = _get_http_tiny_error($response);
    }
  }

  if ($error) {
    if ($args->{'nice'}) {
      return {'error' => [$error]};
    }
    else {
      die "File $url could not be read: $error" unless $args->{'no_exception'};
      return 0;
    }
  }
  else {
    my $compression = defined($args->{'compression'}) || get_compression($url);
    my $uncomp = $compression ? uncompress($content, $compression) : $content;
    if ($args->{'nice'}) {
      return {'content' => $uncomp};
    }
    else {
      return $uncomp;
    }
  }
}

=head2 get_headers

  Arg [1]     : url - URL of file
  Arg [2]     : HashRef - 
                         header (optional) String - name of header
                         nice (optional) Boolean - see introduction
                         compression (optional) String - see introduction
  Example     : my $headers = get_headers(""ftp://ftp.somedomain.org/pub/README");
  Description : Get one or all headers from a remote file
  Returntype  : Hashref containing results (single header or hashref of headers) or errors (ArrayRef)
  Caller      : General
  Status      : Stable

=cut

sub get_headers {
  my ($file, $args) = @_;
  my $url = ref($file) ? $file->location : $file;
  my ($all_headers, $result, $error);

  if ($url =~ /^ftp/) {
    ## TODO - support FTP properly!
    return {'Content-Type' => 1};
  }
  else {
    my %params = ('timeout'       => 10);
    if ($args->{'proxy'}) {
      $params{'http_proxy'}   = $args->{'proxy'};
      $params{'https_proxy'}  = $args->{'proxy'};
    }
    my $http = HTTP::Tiny->new(%params);

    my $response = $http->request('HEAD', $url);
    if ($response->{'success'}) {
      $all_headers = $response->{'headers'};
    }
    else {
      $error = _get_http_tiny_error($response);
    }
  }

  $result = $args->{'header'} ? $all_headers->{$args->{'header'}} : $all_headers;

  if ($args->{'nice'}) {
    return $error ? {'error' => [$error]} : {'headers' => $result};
  }
  else {
    if ($error) {
      die "Could not get headers." unless $args->{'no_exception'};
      return 0;
    }
    else {
      return $result;
    }
  }
}

=head2 get_filesize

  Arg [1]     : url - URL of file
  Arg [2]     : HashRef - 
                         nice (optional) Boolean - see introduction
                         compression (optional) String - compression type
  Example     : my $size = get_filesize(""ftp://ftp.somedomain.org/pub/README");
  Description : Get size of remote file 
  Returntype  : Hashref containing results (Integer - file size in bytes) or errors (ArrayRef)
  Caller      : General
  Status      : Stable

=cut

sub get_filesize {
### 
### @param url - URL of file
### @param Args Hashref 
###         nice (optional) Boolean - see introduction
###         compression String (optional) - compression type
### @return 
  my ($file, $args) = @_;
  $args->{'header'} = 'Content-Length';
  return get_headers($file, $args);
}

sub _get_lwp_useragent_error {
### Convert error responses from LWP::UserAgent into a user-friendly string
### @param response - HTTP::Response object
### @return String
  my $response = shift;

  return 'timeout' unless $response->code;
  return $response->status_line if $response->code >= 400;
  return;
}

sub _get_http_tiny_error {
### Convert error responses from HTTP::Tiny into a user-friendly string
### @param response HashRef 
### @return String
  my $response = shift;

  return 'timeout' unless $response->{'status'};
  if ($response->{'status'} >= 400) {
    return $response->{'status'}.': '.$response->{'reason'};
  }
  return;
}


1;

