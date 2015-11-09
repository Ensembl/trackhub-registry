#
# A class to represent track db data in JSON format,
# to provide methods to check and update the status
# of its tracks.
# An object of this class is built from an ElasticSearch document
#
package Registry::TrackHub::TrackDB;

use strict;
use warnings;

use POSIX qw(strftime);
use Registry;
use Registry::Model::Search;
use Registry::Utils;
use Registry::Utils::URL qw(file_exists);

my %format_lookup = (
		     'bed'    => 'BED',
		     'bb'     => 'bigBed',
		     'bigBed' => 'bigBed',
		     'bw'     => 'bigWig',
		     'bigWig' => 'bigWig',
		     'bam'    => 'bam',
		     'vcf'    => 'vcfTabix',
		     'cram'   => 'cram'
		    );

sub new {
  my ($class, $id) = @_; # arg is the ID of an ES doc
  defined $id or die "Undefined ID";

  my $search_config = Registry->config()->{'Model::Search'};
  my $self = { 
	      _id  => $id,
	      _es  => {
		       client => Registry::Model::Search->new(nodes => $search_config->{nodes}),
		       index  => $search_config->{trackhub}{index},
		       type   => $search_config->{trackhub}{type}
		      }
	     };
  $self->{_doc} = $self->{_es}{client}->get_trackhub_by_id($id);
  defined $self->{_doc} or die "Unable to get document [$id] from store";

  # check the document is in the correct format: ATMO, only v1.0 supported
  my $doc = $self->{_doc};
  exists $doc->{data} and ref $doc->{data} eq 'ARRAY' and
  exists $doc->{configuration} and ref $doc->{configuration} eq 'HASH' or
    die "TrackDB document doesn't seem to be in the correct format";

  bless $self, $class;
  return $self;
}

sub doc {
  return shift->{_doc};
}

sub id {
  return shift->{_id};
}

sub type {
  return shift->{_doc}{type};
}

sub hub {
  return shift->{_doc}{hub};
}

sub version {
  return shift->{_doc}{version};
}

sub file_type {
  return [ sort keys %{shift->{_doc}{file_type}} ];
}

sub created {
  my ($self, $format) = @_;

  return unless $self->{_doc}{created};

  return strftime "%x %X %Z (%z)", localtime($self->{_doc}{created})
    if $format;

  return $self->{_doc}{created};
}

sub updated {
  my ($self, $format) = @_;

  return unless $self->{_doc}{updated};

  return strftime "%x %X %Z (%z)", localtime($self->{_doc}{updated})
    if $format;

  return $self->{_doc}{updated};
}

sub source {
  return shift->{_doc}{source};
}

sub compute_checksum {
  my $self = shift;
  
  my $source_url = $self->{_doc}{source}{url};
  defined $source_url or die sprintf "Cannot get source URL for trackDb %s", $self->id;

  return Registry::Utils::checksum_compute($source_url);
}

sub assembly {
  return shift->{_doc}{assembly};
}

sub status {
  my $self = shift;
  
  return $self->{_doc}{status};
}

sub status_message {
  my $self = shift;

  return $self->{_doc}{status}{message};
}

sub status_last_update {
  my ($self, $format) = @_;

  return unless $self->{_doc}{status}{last_update};

  return strftime "%x %X %Z (%z)", localtime($self->{_doc}{status}{last_update})
    if $format;

  return $self->{_doc}{status}{last_update};
}

sub update_status {
  my $self = shift;

  my $doc = $self->{_doc};
  
  # check doc status
  # another process might have started to check it
  # abandon the task in this case
  #
  # TODO? abandon also if doc has been recently checked
  #
  exists $doc->{status} or die "Unable to read status";
  if ($doc->{status}{message} eq 'Pending') {
    die sprintf "TrackDB document [%s] is already being checked by another process.", $self->{_id};
  }

  # initialise status to pending
  my $last_update = $doc->{status}{last_update};
  $doc->{status}{message} = 'Pending';

  # reindex doc to flag other processes its pending status
  # and refresh the index to immediately commit changes
  $self->{_es}{client}->index(index  => $self->{_es}{index},
			      type   => $self->{_es}{type},
			      id     => $self->{_id},
			      body   => $doc);
  $self->{_es}{client}->indices->refresh(index => $self->{_es}{index});

  # check remote data URLs and record stats
  $doc->{status}{tracks} = 
    {
     total => 0,
     with_data => {
		   total => 0,
		   total_ko => 0
		  }
    };
  $self->_collect_track_info($doc->{configuration});
  $doc->{status}{message} = 
    $doc->{status}{tracks}{with_data}{total_ko}?'Remote Data Unavailable':'All is Well';
  $doc->{status}{last_update} = time;

  # commit status change
  $self->{_es}{client}->index(index  => $self->{_es}{index},
			      type   => $self->{_es}{type},
			      id     => $self->{_id},
			      body   => $doc);
  $self->{_es}{client}->indices->refresh(index => $self->{_es}{index});

  return $doc->{status};
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

	  # determine type
	  my @path = split(/\./, $url);
	  my $index = -1;
	  # handle compressed formats
	  $index = -2 if $path[-1] eq 'gz';
	  $self->{_doc}{file_type}{$format_lookup{$path[$index]}}++;
	}

      }
    }
  }
  
}

1;
