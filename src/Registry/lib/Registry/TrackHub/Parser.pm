=head1 LICENSE

Copyright [2015-2023] EMBL-European Bioinformatics Institute

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

Registry::TrackHub::Parser - Parse a trackDB file

=head1 SYNOPSIS

my $th = Registry::TrackHub->new(url => $URL);
my $tracks = Registry::TrackHub::Parser->new(files => $th->get_genome('hg19')->trackDb)->parse;

=head1 DESCRIPTION

A class providing a method for parsing trackDB configuration files. This is usually used
in conjuction with a Registry::TrackHub object which provides the (relative) path to
the trackDB configuration file for a given assembly.

=head1 BUGS

Metadata fields are not parsed correctly when the format is a sequence of key/value pairs

=cut

#
# A parser of trackDB configuration files
#
package Registry::TrackHub::Parser;

use strict;
use warnings;

use Encode qw(decode_utf8 FB_CROAK);

use Registry::Utils::URL qw(read_file);
use Registry::Utils::Exception;

# AUTOLOAD is completely unnecessary. It is lazy and just makes it harder to debug
use vars qw($AUTOLOAD);

=head1 METHODS

=cut

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;

  return $self->{$attr};
}

=head2 new

  Arg [1]     : Hash - constructor parameters (required)
                     - files - ArrayRef a list of trackDB configuration files, usually one item
  Example     : Registry::TrackHub::Parser->new(files => $th->get_genome('hg19')->trackDB);
  Description : Build a Registry::TrackHub::Parser object
  Returntype  : Registry::TrackHub::Parser
  Exceptions  : Thrown if required parameter is not provided
  Caller      : Registry::TrackHub::Translator
  Status      : Stable

=cut

sub new {
  my ($class, %args) = @_;

  defined $args{files} || Registry::Utils::Exception->throw("Undefined 'files' parameter in instantiation");
  my $self = \%args || {};
  
  bless $self, $class;
  return $self;
}

=head2 parse

  Arg [1]     : None
  Example:    : my $tracks = $parser->parse();
  Description : Parse the trackDB configuration file(s) for a particular assembly
                in a given hub
  Returntype  : HashRef - contains the hierarchical structure of tracks information
  Exceptions  : None
  Caller      : Registry::TrackHub::Translator
  Status      : Stable

=cut

sub parse {
  my $self = shift;

  my $tracks = {};
  foreach (@{$self->files}) {
    my $response = read_file($_, { 'nice' => 1 });
    Registry::Utils::Exception->throw(join("\n", @{$response->{error}}) )
      if $response->{error};
    $response->{content} = Encode::decode_utf8($response->{content}, Encode::FB_CROAK);
    $self->_parse_file_content($tracks, $response->{content} =~ s/\r//gr, $_);
  }
  
  return $tracks;
}

sub _parse_file_content {
  my ($self, $tracks, $content, $file) = @_;

  my $url      = $file =~ s|^(.+)/.+|$1|r; # URL relative to the file (up until the last slash before the file name)
  my @contents = split /track /, $content;
  shift @contents;
 
  ## Some hubs don't set the track type, so...
  my %format_lookup = (
		       'bed'    => 'bed',
		       'bb'     => 'bigBed',
		       'bigBed' => 'bigBed',
		       'bw'     => 'bigWig',
		       'bigWig' => 'bigWig',
		       'bam'    => 'bam',
		       'gz'     => 'vcfTabix',
		       'cram'   => 'cram'
                      );
 
  foreach (@contents) {
    my @lines = split /\n/;
    my (@track, $multi_line);
    
    foreach (@lines) {
      next unless /\w/;
      
      s/(^\s*|\s*$)//g; # Trim leading and trailing whitespace
      
      if (s/\\$//g) { # Lines ending in a \ are wrapped onto the next line
        $multi_line .= $_;
        next;
      }
      
      push @track, $multi_line ? "$multi_line$_" : $_;
      
      $multi_line = '';
    }
    
    my $id = shift @track;
    next unless defined $id;
    
    $id = 'Unnamed' if $id eq '';
   
    foreach (@track) {
      my ($key, $value) = split /\s+/, $_, 2;
      
      next if $key =~ /^#/; # Ignore commented-out attributes
      
      if ($key eq 'type') {
        my @values = split /\s+/, $value;
        my $type   = lc shift @values;
        # $type   = 'vcf' if $type eq 'vcftabix';
        
        $tracks->{$id}{$key} = $type;
        
        if ($type eq 'bigbed') {
          # this does not work for views,
          # standard fields remains undefined
          $tracks->{$id}{'standard_fields'}   = shift @values;
          if (defined $tracks->{$id}{'standard_fields'}) {
            $tracks->{$id}{'additional_fields'} = $values[0] eq '+' ? 1 : 0;
            $tracks->{$id}{'configurable'}      = $values[0] eq '.' ? 1 : 0; # Don't really care for now
          } else {
            delete $tracks->{$id}{'standard_fields'};
          }
        } elsif ($type eq 'bigwig') {
          $tracks->{$id}{'signal_range'} = \@values;
        }
      } elsif ($key eq 'bigDataUrl') {
        if ($value =~ /^\//) { ## path is relative to server, not to hub.txt
          (my $root = $url) =~ s/^(ftp|https?):\/\/([\w|-|\.]+)//;
          $tracks->{$id}{$key} = $root.$value;
        }
        else {
          $tracks->{$id}{$key} = $value =~ /^(ftp|https?):\/\// ? $value : "$url/$value";
        }
      } else {
        if ($key eq 'parent' || $key =~ /^subGroup[0-9]/) {
          my @values = split /\s+/, $value;
          
          if ($key eq 'parent') {
            $tracks->{$id}{$key} = $values[0]; # FIXME: throwing away on/off setting for now
            next;
          } else {
            $tracks->{$id}{$key}{'name'}  = shift @values;
            $tracks->{$id}{$key}{'label'} = shift @values;
            
            $value = join ' ', @values;
          }
        }
        
        # Deal with key=value attributes.
        # These are in the form key1=value1 key2=value2, but values can be quotes strings with spaces in them.
        # Short and long labels may contain =, but in these cases the value is just a single string
        if ($value =~ /=/ && $key !~ /^(short|long)Label$/) {

          #
          # NOTE
          # the following commented fragments do not correctly parse
          # metadata when key/value pairs contain text enclosed in double
          # quotes separated by spaces.
          #
          # my ($k, $v);
          # my @pairs = split /\s([^=]+)=/, " $value";
          # shift @pairs;
          
          # for (my $i = 0; $i < $#pairs; $i += 2) {
          #   $k = $pairs[$i];
          #   $v = $pairs[$i + 1];
            
          #   # If the value starts with a quote, but doesn't end with it, this value contains the pattern \s(\w+)=, so has been split multiple times.
          #   # In that case, append all subsequent elements in the array onto the value string, until one is found which closes with a matching quote.
          #   if ($v =~ /^("|')/ && $v !~ /$1$/) {
          #     my $quote = $1;
              
          #     for (my $j = $i + 2; $j < $#pairs; $j++) {
          #       $v .= "=$pairs[$j]";
                
          #       if ($pairs[$j] =~ /$quote$/) {
          #         $i += $j - $i - 1;
          #         last;
          #       }
          #     }
          #   }
            
          #   $v =~ s/(^["']|['"]$)//g; # strip the quotes from the start and end of the value string
            
          #   $tracks->{$id}{$key}{$k} = $v;
          # }

          # PB with URLs containing =, remove key/value pairs containing them
          $value =~ s/\w+?="[^="]+?=[^"]+?"\s//g;

          my @tokens1 = split /=/, $value; 
          my @tokens2;

          for (my $i = 0; $i <= $#tokens1; $i++) {
            if ($tokens1[$i] =~ /^[\w:_]+$/) {
              push @tokens2, $tokens1[$i];
            } elsif ($tokens1[$i] =~ /"|'/) {
              push @tokens2, grep { defined $_ } $tokens1[$i] =~ /"(.*)"|'(.*)'|([\w:_]+)/g;;
            } else {
              push @tokens2, split(/\s+/, $tokens1[$i]);
            }
          }

          for (my $i = 0; $i < $#tokens2; $i += 2) {
            $tracks->{$id}{$key}{$tokens2[$i]} = $tokens2[$i+1];
          }
        } else {
          $tracks->{$id}{$key} = $value;
        }
      }
    }
    
    # filthy hack to support superTrack setting being used as parent, because hubs are incorrect.
    $tracks->{$id}{'parent'} = delete $tracks->{$id}{'superTrack'} 
      if $tracks->{$id}{'superTrack'} && $tracks->{$id}{'superTrack'} !~ /^on/ && !$tracks->{$id}{'parent'};


    # any track which doesn't have any of these is definitely invalid
    if ($tracks->{$id}{'type'} || $tracks->{$id}{'shortLabel'} || $tracks->{$id}{'longLabel'}) {
      $tracks->{$id}{'track'}           = $id;
      $tracks->{$id}{'description_url'} = "$url/$id.html" unless $tracks->{$id}{'parent'};
      
      if ($tracks->{$id}{'bigDataUrl'} and not $tracks->{$id}{'type'}) {
        ## Set type based on file extension
        my @path = split(/\./, $tracks->{$id}{'bigDataUrl'});
        $tracks->{$id}{'type'} = $format_lookup{$path[-1]};
      }
      
      if ($tracks->{$id}{'dimensions'}) {
        # filthy last-character-of-string hack to support dimensions in the same way as UCSC
        my @dimensions = keys %{$tracks->{$id}{'dimensions'}};
        $tracks->{$id}{'dimensions'}{lc substr $_, -1, 1} = delete $tracks->{$id}{'dimensions'}{$_} for @dimensions;
      }
    } else {
      delete $tracks->{$id};
    }
  }
  
  # Make sure the track hierarchy is ok
  foreach (values %{$tracks}) {
    Registry::Utils::Exception->throw(sprintf "File %s: parent track %s is missing", $file, $_->{'parent'})
      if $_->{'parent'} && !$tracks->{$_->{'parent'}};
  }
  
}

1;
