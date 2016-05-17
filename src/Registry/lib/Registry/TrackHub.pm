#
# A class to represent a top-level track hub container
#
package Registry::TrackHub;

use strict;
use warnings;

use Registry::TrackHub::Genome;
use Registry::Utils qw(run_cmd);
use Registry::Utils::URL qw(read_file);
use Encode qw(decode_utf8 FB_CROAK);

use vars qw($AUTOLOAD);

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

  defined $args{url} or die "Undefined URL parameter.";

  my $self = \%args;
  bless $self, $class;

  # check hub is compliant to UCSC specs
  # use hubCheck program to check a track data hub for integrity
  $self->_hub_check() unless $self->{permissive};

  # fetch hub info
  $self->_get_hub_info();

  return $self;
}

sub assemblies {
  my $self = shift;
  
  return keys %{$self->genomes};
}

sub get_genome {
  my ($self, $assembly) = @_;
  defined $assembly or die "Cannot get genome data: undefined assembly argument";

  exists $self->genomes->{$assembly} or
    die "No genome data for assembly $assembly";

  return $self->genomes->{$assembly};
}

# TODO: finish check
sub _hub_check {
  my $self = shift;
  my $url = $self->url;

  my @split_url = split '/', $url;
  my $hub_file;
  
  if ($split_url[-1] =~ /[.?]/) {
    $hub_file = pop @split_url;
    $url      = join '/', @split_url;
  } else {
    $hub_file = 'hub.txt';
    $url      =~ s|/$||;
  }

  my $cmd = sprintf("hubCheck -checkSettings -test -noTracks %s/%s", $url, $hub_file);
  my ($rc, $output) = Registry::Utils::run_cmd($cmd);
  if ($output =~ /problem/) {
    my @lines = split /\n/, $output;
    shift @lines;
    for my $line (@lines) {
      # Raise exception as soon as we detect some problem
      # which is not related to some deprecated feature
      # Also skip in case of some unsupported file formats like cram
      next if $line =~ /deprecated|cram/;

      die "hubCheck report:\n$output\n\nPlease refer to the (versioned) spec document: http://genome-test.cse.ucsc.edu/goldenPath/help/trackDb/trackDbHub.html";
    }
  }
}

sub _get_hub_info {
  my $self = shift;
  my $url = $self->url;

  my @split_url = split '/', $url;
  my $hub_file;
  
  if ($split_url[-1] =~ /[.?]/) {
    $hub_file = pop @split_url;
    $url      = join '/', @split_url;
  } else {
    $hub_file = 'hub.txt';
    $url      =~ s|/$||;
  }

  my $file_args = { nice => 1 };
  my $response = read_file("$url/$hub_file", $file_args);
  my $content;
 
  if ($response->{error}) {
    push @{$response->{error}}, "Please check the source URL in a web browser.";
    die join("\n", @{$response->{error}});
  }
  $content = Encode::decode_utf8($response->{'content'}, Encode::FB_CROAK);

  my %hub_details;

  ## Get file name for file with genome info
  foreach (split /\n/, $content) {
    my @line = split /\s/, $_, 2;
    $line[1] =~ s/^\s+|\s+$//g; # trim left/right spaces
    $hub_details{$line[0]} = $line[1];
  }
  die 'No genomesFile found' unless $hub_details{genomesFile};
 
  ## Now get genomes file and parse 
  $response = read_file("$url/$hub_details{'genomesFile'}", $file_args); 
  die join("\n", @{$response->{error}}) if $response->{error};
  
  $content = $response->{content};

  (my $genome_file = $content) =~ s/\r//g;
  my $genomes;
  my @lines = split /\n/, $genome_file;
  my ($genome, $file, %ok_genomes);
  foreach (split /\n/, $genome_file) {
    my ($k, $v) = split(/\s/, $_);
    next unless $k =~ /^\w/;

    if ($k =~ /genome/) {
      $genome = $v;
      $genomes->{$genome} = Registry::TrackHub::Genome->new(assembly => $genome);
      ## Check if any of these genomes are available on this site,
      ## because we don't want to waste time parsing them if not!
      # if ($assembly_lookup && $assembly_lookup->{$genome}) {
      #  $ok_genomes{$genome} = 1;
      # }
      # else {
      #  $genome = undef;
      # }
    } else {
      $genomes->{$genome}->$k($v);
    }
  }

  ## Parse list of config files
  my @errors;

  foreach my $genome (keys %{$genomes}) {
    $file = $genomes->{$genome}->trackDb;
 
    if ($file =~ /^http|^ftp/) { # path to trackDB could be remote
      $response = read_file("$file", $file_args);
    } else {
      $response = read_file("$url/$file", $file_args);  
    }
    push @errors, "$genome ($url/$file): " . @{$response->{error}}
      if $response->{error};
    $content = $response->{content};
    
    my @track_list;
    $content =~ s/\r//g;
    
    # Hack here: Assume if file contains one include it only contains includes and no actual data
    # Would be better to resolve all includes (read the files) and pass the complete config data into 
    # the parsing function rather than the list of file names
    foreach (split /\n/, $content) {
      next if /^#/ || !/\w+/ || !/^include/;
      
      s/^include //;
      push @track_list, "$url/$_";
    }
    
    if (scalar @track_list) {
      ## replace trackDb file location with list of track files
      $genomes->{$genome}->trackDb(\@track_list);
    } else {
      if ($file =~ /^http|^ftp/) {
	$genomes->{$genome}->trackDb([ "$file" ]);	
      } else {
	$genomes->{$genome}->trackDb([ "$url/$file" ]);	
      }
    }
  }

  die join("\n", @errors) if scalar @errors;

  map { $self->$_($hub_details{$_}) } keys %hub_details;
  $self->genomes($genomes);

  return;
}

1;
