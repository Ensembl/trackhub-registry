=head1 LICENSE

Copyright [2015-2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

#
# A parser of trackDB configuration files
#
package Registry::TrackHub::Parser;

use strict;
use warnings;
use HTML::Restrict;

use Encode qw(decode_utf8 FB_CROAK);

use Registry::Utils::URL qw(read_file);

use vars qw($AUTOLOAD);

open(VL, ">valid_log.out");
open(IV, ">invalid_log.out");
open(VLP, ">valid_pair_log.out");

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;
  return $self->{$attr};
}


sub new {
  my ($class, %args) = @_;
  
  defined $args{files} || die "Undefined files parameter";
  my $self = \%args || {};
  
  bless $self, $class;
  return $self;
}

sub parse {
  my $self = shift;
  my $tracks = {};
  foreach (@{$self->files}) {
#  	my $tmp = 'http://localhost:3000/static/example/roadmap_both_02182015_trackDb_1000.txt';
#  	print "$tmp\n";
    my $response = read_file($_, { 'nice' => 1 });
#    my $response = read_file($tmp, { 'nice' => 1 });
    die join("\n", @{$response->{error}})
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
		       'bigbed' => 'bigBed',
		       'bw'     => 'bigWig',
		       'bigWig' => 'bigWig',
		       'bigwig' => 'bigWig',
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

	    # PB with URLs containing =, remove key/value pairs containing them
	     # $value =~ s/\w+?="[^="]+?=[^"]+?"\s//g;
          my $valid_tokens = $self->_get_key_value_tokens($value);

	      while (my ($key_token, $value_token) = each %$valid_tokens) {
	        $tracks->{$id}{$key}{$key_token} = $value_token;
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
    die sprintf "File %s: parent track %s is missing", $file, $_->{'parent'}
      if $_->{'parent'} && !$tracks->{$_->{'parent'}};
  }
  
}

sub _get_key_value_tokens{
	  my ($self, $value) = @_;

	  # PB with URLs containing =, remove key/value pairs containing them
	  
	  # Check if the string contains HTML tags
	  my $hr = HTML::Restrict->new();
	  my $plain_text = $hr->process( $value );
	  
	  
	  $plain_text =~ s/\w+?="[^="]+?=[^"]+?"\s//g;

	  my @tokens1 = split /=/, $plain_text; 
	  my @tokens2;
	  for (my $i = 0; $i <= $#tokens1; $i++) {
	  	my $tmp = $tokens1[$i];

	    if ($tokens1[$i] =~ /^[\w:_]+$/) {
	      push @tokens2, $tokens1[$i];
	    } elsif ($tokens1[$i] =~ /"|'/) {
	      my $quoted_str = $tokens1[$i];
	      if ($quoted_str =~ /"(.*?)"\s+"(.*?)"|'(.*?)'\s+'(.*?)'/g){ #eg: "Epigenome_Mnemonic"="GI.CLN.MUC" "Standardized_Epigenome_name"="Colonic Mucosa"
	      	my $tmp_token1 = $1;
	      	my $tmp_token2 = $2;
	      	$tmp_token1 =~ s/"|'//g;
	      	$tmp_token2 =~ s/"|'//g;
	      	
	        push @tokens2, $tmp_token1, $tmp_token2;
	      } elsif ($quoted_str =~ /"(.*?)"\s+([\w-]+)|'(.*?)'\s+([\w-]+)/g){  #eg: GEO_Accession="GSM1127100" sample_alias="Breast Fibroblast RM071, batch 1" 
	      	my $tmp_token1 = $1;
	      	my $tmp_token2 = $2;
	      	$tmp_token1 =~ s/"|'//g;
	      	$tmp_token2 =~ s/"|'//g;
	        push @tokens2, $tmp_token1, $tmp_token2;
	      }else{
	      	my $tmp_token1 = $tokens1[$i];
	      	$tmp_token1 =~ s/"|'//g;
	        push @tokens2, $tmp_token1;
	      }
	      
	      #push @tokens2, grep { defined $_ } $tokens1[$i] =~ /\"(.*)\"|\'(.*)\'|(.*)\"|\"(.*)|\'(.*)|(.*)\'|([\w:_]+)/g;;
	    } else {
	      push @tokens2, split(/\s+/, $tokens1[$i]);
	    }

	  }
	  my $valid_key_value_tokens = {};
	  for (my $i = 0; $i < $#tokens2; $i += 2) {
	      	
	      	my $key_token = $tokens2[$i];
	      	my $value_token = $tokens2[$i+1];
	      	
	      	next if length($key_token) <=1;
	      	next if length($value_token) < 1;
	      	next unless $self->_is_valid_key_token($key_token);
	      	
	      	if (defined $key_token && defined $value_token){
	      	  $valid_key_value_tokens->{$key_token} = $value_token;
	      	}
	  }
     
     return $valid_key_value_tokens;

}

sub _is_valid_key_token{
	my ($self, $key_token) = @_;

    #if ($key_token =~ /^[a-zA-Z0-9_\/]*$/){
    if ($key_token =~ /^[a-zA-Z0-9_\/]*$/){

	  if($key_token =~ /^[ATCGN]+$/){
		return 0;
	   }
	
	  if($key_token =~ /^[0-9]+$/){
	  	print IV $key_token, "\n";
		return 0;
	  }
	  return 1;
    }
  return 0;
}

1;
