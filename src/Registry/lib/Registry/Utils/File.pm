=head1 LICENSE

Copyright [2015-2022] EMBL-European Bioinformatics Institute

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

Registry::Utils::File - File utilities

=head1 SYNOPSIS


=head1 DESCRIPTION

Library for location-independent file functions such as compression support.
Most of the provided functions are borrowed from the Ensembl web team.

=cut

package Registry::Utils::File;

### 

use strict;
use warnings;
use Compress::Zlib qw//;
use Compress::Bzip2;
use IO::Uncompress::Bunzip2;
use Carp qw/confess/;
use Exporter qw(import);
our @EXPORT_OK = qw(slurp_file sanitise_filename get_filename get_extension get_compression uncompress);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);
use File::Spec;

=head1 METHODS

=head2 slurp_file

  Arg [1]     : String - the name of the file
  Example     : my $content = slurp_file('tmp.txt');
  Description : Load the content of a file into a scalar
  Returntype  : A string with the file content
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub slurp_file {
  my $file = shift;
  defined $file or confess "Undefined file argument";

  my $string;
  {
    local $/=undef;
    open my $fh, '<',"$file" or confess sprintf "Couldn't open file %s: %s", File::Spec->rel2abs($file), $!;
    $string = <$fh>;
    close $fh;
  }
  
  return $string;
}

=head2 sanitise_filename

  Arg [1]     : String - the name of the file
  Example     : my $better_file_name = sanitise_filename($file);
  Description : Users often break the rules for safe, Unix-friendly filenames
                so clean up input
  Returntype  : A string with the sanitised file name
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub sanitise_filename {
  my $file_name = shift;
  $file_name =~ s/[^\w\.]/_/g;
  return $file_name;
}

=head2 get_filename

  Arg [1]     : String - the file path
  Arg [2]     : String - mode (optional), either 'read' or 'write'
  Example     : my $filename = get_filename('/home/username/tmp.txt');
  Description : Get filename parsing it from a path
  Returntype  : A string containing the name of the file without path
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub get_filename {
  my ($file, $mode) = @_;
  my @path = split('/', $file);
  return $path[-1];
}

=head2 get_extension

  Arg [1]     : String - the file name
  Example     : my $ext = get_extension('/home/username/tmp.txt');
  Description : Get file extension parsing it from a path. Note that the 
                returned string does not include any compression extension
  Returntype  : A string containing the extension of the file
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub get_extension {
  my ($file) = @_;
  my $extension = '';

  my $filename = get_filename($file);
  my @parts = split(/\./, $filename);
  $extension = pop @parts;
  if ($extension =~ /zip|gz|bz/) {
    $extension = pop @parts;
  }
  
  return $extension;
}

=head2 get_compression

  Arg [1]     : String - the file name
  Example     : my $cpr = get_compression('/home/username/tmp.txt.gz');
  Description : Helper method to check if file is compressed and, if so,
                what kind of compression appears to have been used.
  Returntype  : A string containing the compression type of the file
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub get_compression {
  my ($file) = @_;
  my $compression;

  return 'gz'   if $file =~ /\.gz$/;
  return 'zip'  if $file =~ /\.zip$/;
  return 'bz'   if $file =~ /\.bz2?$/;
  return;
}

=head2 uncompress

  Arg [1]     : ScalarRef - reference to file content
  Arg [2]     : String - compression type (Optional)
  Example     : uncompress($file_content_ref);
  Description : Compression support for remote files, which cannot use the built-in support
                in Bio::EnsEMBL::Utils::IO. If not passed an explicit compression type, will
                attempt to work out compression type based on the file content
  Returntype  : None
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub uncompress {
  my ($content_ref, $compression) = @_;
  $compression ||= ''; ## avoid undef, so we don't have to keep checking it exists!
  my $temp;

  if ($compression eq 'zip' || 
      ord($$content_ref) == 31 && ord(substr($$content_ref,1)) == 157 ) { ## ZIP...
    $temp = Compress::Zlib::uncompress($$content_ref);
    $$content_ref = $temp;
  } 
  elsif ($compression eq 'gz' || 
      ord($$content_ref) == 31 && ord(substr($$content_ref,1)) == 139 ) { ## GZIP...
    $temp = Compress::Zlib::memGunzip($$content_ref);
    $$content_ref = $temp;
  } 
  elsif ($compression eq 'bz' || $$content_ref =~ /^BZh([1-9])1AY&SY/ ) {                            ## GZIP2
    my $temp = Compress::Bzip2::decompress($content_ref); ## Try to uncompress a 1.02 stream!
    unless($temp) {
      my $T = $$content_ref;
      my $status = IO::Uncompress::Bunzip2::bunzip2 \$T,\$temp;            ## If this fails try a 1.03 stream!
    }
    $$content_ref = $temp;
  }

  return;
}


1;

