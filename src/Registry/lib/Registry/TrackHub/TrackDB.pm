#
# A class to represent track db data in JSON format
#
package Registry::TrackHub::TrackDB;

use strict;
use warnings;

use JSON;
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

  my $self = { _doc => $doc };
  bless $self, $class;

  $self->_get_track_info();

  return $self;
}

sub _get_track_info {
  my $self = shift;
  my $doc = $self->{_doc};
  
  # collect all bigDataURLs and check them
  $self->{tracks} = {};
  $self->_collect_track_info($doc->{configuration});
}

sub _collect_track_info {
  my ($self, $hash, $tracks) = @_;
  foreach my $track (keys %{$hash}) { # key is track name
    if (ref $hash->{$track} eq 'HASH') {
      foreach my $attr (keys %{$hash->{$track}}) {
	next unless $attr =~ /bigdataurl/i or $key eq 'members';
	if ($attr eq 'members') {
	  $self->_collect_track_info($hash->{$track}{$attr}) if ref $hash->{$track}{$attr} eq 'HASH';
	} else {
	  my $url = $hash->{$track}{$attr};
	  my $response = file_exists($url, { nice => 1 });
	  if ($response->{error}) {
	    push @{$self->{tracks}{$track}}, ($url, 0, $response->{error});
	  } elsif ($response->{success}) {
	    push @{$self->{tracks}{$track}}, ($url, 1);
	  } else {
	    die "Unrecognised response code";
	  }
	}

      }
    }
  }

}

1;
