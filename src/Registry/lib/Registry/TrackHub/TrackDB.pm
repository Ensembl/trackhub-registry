#
# A class to represent track db data in JSON format,
# to provide methods to check and update the status
# of its tracks.
#
package Registry::TrackHub::TrackDB;

use strict;
use warnings;

use Registry;
use Registry::Model::Search;
use Registry::Utils::URL qw(file_exists read_file);

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
  my ($class, $doc) = @_;
  defined $doc or die "Undefined doc parameter.";
  # check the document is in the correct format: ATMO, only v1.0 supported
  exists $doc->{data} and ref $doc->{data} eq 'ARRAY' and
  exists $doc->{configuration} and ref $doc->{configuration} eq 'HASH' or
    die "TrackDB document doesn't seem to be in the correct format";

  my $search_config = Registry->config()->{'Model::Search'};
  my $self = { 
	      _doc => $doc,
	      _es  => {
		       client => Registry::Model::Search->new(nodes => $search_config->{nodes}),
		       index  => $search_config->{index},
		       type   => $search_config->{type}{trackhub}
		      }
	     };
  bless $self, $class;
  
  return $self;
}

sub doc {
  return shift->{_doc};
}

sub status {
  my $self = shift;
  
  return $self->{_doc}{status};
}

sub status_last_update {
  my $self = shift;

  return localtime($self->{_doc}{status}{last_update});
}

sub update_status {
  my $self = shift;

  my $doc = $self->{_doc};
  $doc->{status} = 
    { 
     tracks  => {
		 total => 0,
		 with_data => {
			       total => 0,
			       total_ko => 0
			      }
		},
     message => 'All is Well' 
    };

  $self->_collect_track_info($doc->{configuration});
  $doc->{status}{message} = 'Remote Data Unavailable' if $doc->{status}{tracks}{with_data}{total_ko};
  $doc->{status}{last_update} = time();

  # TODO: reindex the document
  
  return $self->{_doc}{status};
}

sub track_info {
  my $self = shift;
  defined $self->{tracks} or die "Unknown status";

  return $self->{tracks};
}

sub _collect_track_info {
  my ($self, $hash) = @_;
  foreach my $track (keys %{$hash}) { # key is track name
    ++$self->{_doc}{status}{tracks}{total};

    if (ref $hash->{$track} eq 'HASH') {
      foreach my $attr (keys %{$hash->{$track}}) {
	next unless $attr =~ /bigdataurl/i or $attr eq 'members';
	if ($attr eq 'members') {
	  $self->_collect_track_info($hash->{$track}{$attr}) if ref $hash->{$track}{$attr} eq 'HASH';
	} else {
	  ++$self->{_doc}{status}{tracks}{with_data}{total};

	  my $url = $hash->{$track}{$attr};
	  my $response = file_exists($url, { nice => 1 });
	  if ($response->{error}) {
	    $self->{_doc}{status}{tracks}{with_data}{total_ko}++;
	    $self->{_doc}{status}{tracks}{with_data}{ko}{$track} = 
	      [ $url, $response->{error}[0] ];
	  }
	}

      }
    }
  }
  
}

1;
