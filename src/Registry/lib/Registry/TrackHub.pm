#
# A class to represent a top-level track hub container
#
package Registry::TrackHub;

use strict;
use warnings;

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

sub trackdb_conf_for_assembly {
  my ($self, $assembly) = @_;
  defined $assembly or
    Catalyst::Exception->throw("Undefined assembly");

  exists $self->genomes->{$assembly} or
    Catalyst::Exception->throw("Cannot retrieve data for assembly $assembly");

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
  my %genome_info;
  my @lines = split /\n/, $genome_file;
  my ($genome, $file, %ok_genomes);
  foreach (split /\n/, $genome_file) {
    my ($k, $v) = split(/\s/, $_);
    if ($k =~ /genome/) {
      $genome = $v;
      ## Check if any of these genomes are available on this site,
      ## because we don't want to waste time parsing them if not!
      # if ($assembly_lookup && $assembly_lookup->{$genome}) {
      #  $ok_genomes{$genome} = 1;
      # }
      # else {
      #  $genome = undef;
      # }
    } elsif ($genome && $k =~ /trackDb/) {
      $file = $v;
      $genome_info{$genome} = $file;
      ($genome, $file) = (undef, undef);
    }
  }

  ## Parse list of config files
  my @errors;

  foreach my $genome (keys %genome_info) {
    $file = $genome_info{$genome};
 
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
      $genome_info{$genome} = \@track_list;
    } else {
      $genome_info{$genome} = [ "$url/$file" ];
    }
  }

  Catalyst::Exception->throw(join("\n", @errors)) if scalar @errors;

  map { $self->$_($hub_details{$_}) } keys %hub_details;
  $self->genomes(\%genome_info);

  return;
}

1;
