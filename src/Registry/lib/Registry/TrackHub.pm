#
# A class to represent a top-level track hub container
#
package Registry::TrackHub;

use strict;
use warnings;

use Registry::TrackHub::Genome;
use Registry::Utils::URL qw(read_file);
use Catalyst::Exception;

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

  $self->_get_hub_info();

  return $self;
}

sub assemblies {
  my $self = shift;
  
  return keys %{$self->genomes};
}

sub get_genome {
  my ($self, $assembly) = @_;
  defined $assembly or Catalyst::Exception->throw("Cannot get genome data: undefined assembly argument");

  exists $self->genomes->{$assembly} or
    Catalyst::Exception->throw("No genome data for assembly $assembly");

  return $self->genomes->{$assembly};
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
    push @{$response->{error}}, "Please the check the source URL in a web browser.";
    Catalyst::Exception->throw(join("\n", @{$response->{error}}));
  }
  $content = $response->{'content'};

  my %hub_details;

  ## Get file name for file with genome info
  foreach (split /\n/, $content) {
    my @line = split /\s/, $_, 2;
    $hub_details{$line[0]} = $line[1];
  }
  Catalyst::Exception->throw('No genomesFile found') unless $hub_details{genomesFile};
 
  ## Now get genomes file and parse 
  $response = read_file("$url/$hub_details{'genomesFile'}", $file_args); 
  Catalyst::Exception->throw(join("\n", @{$response->{error}})) if $response->{error};
  
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
 
    $response = read_file("$url/$file", $file_args); 
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
      $genomes->{$genome}->trackDb([ "$url/$file" ]);
    }
  }

  Catalyst::Exception->throw(join("\n", @errors)) if scalar @errors;

  map { $self->$_($hub_details{$_}) } keys %hub_details;
  $self->genomes($genomes);

  return;
}

1;
