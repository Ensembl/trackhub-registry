#
# A class to represent a translator from UCSC-style trackdb
# documents to the corresponding JSON specification
#
package Registry::TrackHub::Translator;

use strict;
use warnings;

use JSON;
use Catalyst::Exception;

use Registry::TrackHub;
use Registry::TrackHub::Parser;

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
  
  $args{version} ||= Registry->config()->{TrackHub}{json}{version};
  defined $args{version} or Catalyst::Exception->throw("Undefined version");

  my $self = \%args;
  bless $self, $class;

  return $self;
}

#
# TODO
# validate JSON docs, use Registry->config()->{TrackHub}{json}{schema};
#
sub translate {
  my ($self, $url, $assembly) = @_;

  my $dispatch = 
    {
     '1.0' => sub { $self->to_json_1_0(@_) }
    }->{$self->version};

  Catalyst::Exception->throw(sprintf "Version %d not supported", $self->version) 
      unless $dispatch;

  my $trackhub = Registry::TrackHub->new(url => $url);
  
  my $docs;
  unless ($assembly) { 
    # assembly not specified
    # translate tracksDB conf for all assemblies stored in the Hub
    foreach my $assembly ($trackhub->assemblies) {
      push @{$docs}, $dispatch->(trackhub => $trackhub, 
				 assembly => $assembly);
    }
  } else {
    push @{$docs}, $dispatch->(trackhub => $trackhub, 
			       assembly => $assembly);
  }

  scalar @{$docs} or 
    Catalyst::Exception->throw("Something went wrong. Couldn't get any translated JSON from hub");

  return $docs;
}

sub to_json_1_0 {
  my ($self, %args) = @_;
  my ($trackhub, $assembly) = ($args{trackhub}, $args{assembly});
  defined $trackhub and defined $assembly or
    Catalyst::Exception->throw("Undefined trackhub and/or assembly argument");

  my $genome = $trackhub->get_genome($assembly);

  my $doc = 
    {
     version => '1.0',
     hub     => $trackhub->longLabel,
     # add the original trackDb file(s) content
     trackdb => $genome->get_trackdb_content
    };

  $self->_add_genome_info($genome, $doc);
  my $tracks = Registry::TrackHub::Parser->new(files => $genome->trackDb)->parse;

  return to_json($doc);
}

#
# Add species/assembly info
#
# I presume this can be shared across translations
# to different versions
#
sub _add_genome_info {
  my ($self, $genome, $doc) = @_;

}

1;
