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

=head1 CONTACT

Please email comments or questions to the Trackhub Registry help desk
at C<< <http://www.trackhubregistry.org/help> >>

Questions may also be sent to the public Trackhub Registry list at
C<< <https://listserver.ebi.ac.uk/mailman/listinfo/thregistry-announce> >>

=head1 NAME

Registry::TrackHub::TrackDB - Interface to a trackDB JSON document

=head1 SYNOPSIS

my $trackdb = Registry::TrackHub::TrackDB->new($id);
print "TrackDB $id refers to assembly ", $trackdb->assembly, "\n";

print "Updating status..." && $trackdb->update_status();

=head1 DESCRIPTION

A class to represent track db data in JSON format, to provide methods to get/set informantion,
check and update the status of its tracks. An object of this class is built from an ElasticSearch 
document.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

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
		     'bb'     => 'BigBed',
		     'bigBed' => 'BigBed',
		     'bw'     => 'BigWig',
		     'bigWig' => 'BigWig',
		     'bam'    => 'BAM',
		     'gz'     => 'VCFTabix',
		     'cram'   => 'CRAM'
		    );

=head1 METHODS

=head2 new

  Arg[1]:     : Scalar - the id of the Elasticsearch document (required)
  Example     : Registry::TrackHub::TrackDB->new(1);
  Description : Build a Registry::TrackHub::TrackDB object
  Returntype  : Registry::TrackHub::TrackDB
  Exceptions  : Thrown if required parameter is not provided
  Caller      : Registry::Controller::User
  Status      : Stable

=cut

sub new {
  my ($class, $id) = @_; # arg is the ID of an ES doc
  defined $id or die "Undefined ID";
  
  # the nodes parameter must be passed passed when we invoke the 
  # constructor outside the Catalyst loop, since we cannot access
  # the Registry configuration object
  my $config = Registry->config()->{'Model::Search'};

  my $self = { 
	      _id  => $id,
	      _es  => {
		       client => Registry::Model::Search->new(nodes => $config->{nodes}),
		       index  => $config->{trackhub}{index},
		       type   => $config->{trackhub}{type}
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

=head2 doc

  Arg[1]:     : None
  Example     : my $doc = $trackdb->doc();
  Description : Returns the (JSON) doc
  Returntype  : HashRef - the document as a hash of attribute/value pairs
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub doc {
  return shift->{_doc};
}

=head2 id

  Arg[1]:     : None
  Example     : my $id = $trackdb->id();
  Description : Returns the ID of the trackDB document
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub id {
  return shift->{_id};
}

=head2 type

  Arg[1]:     : None
  Example     : my $type = $trackdb->type();
  Description : Returns the data type of the trackDB represented by the document
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub type {
  return shift->{_doc}{type};
}

=head2 hub

  Arg[1]:     : None
  Example     : my $hub = $trackdb->hub();
  Description : Returns the hub portion of the trackDB document
  Returntype  : HashRef
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub hub {
  return shift->{_doc}{hub};
}

=head2 version

  Arg[1]:     : None
  Example     : my $v = $trackdb->version();
  Description : Returns the (JSON schema) version of the trackDB JSON document
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub version {
  return shift->{_doc}{version};
}

=head2 file_type

  Arg[1]:     : None
  Example     : my $file_types = $trackdb->file_type();
  Description : Returns the file types of the files referenced by the tracks in the trackDB
  Returntype  : ArrayRef
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub file_type {
  return [ sort keys %{shift->{_doc}{file_type}} ];
}

=head2 created

  Arg[1]:     : None
  Example     : my $created = $trackdb->created();
  Description : Returns the timestamp representing the time when the trackDB was initially stored
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub created {
  my ($self, $format) = @_;

  return unless $self->{_doc}{created};

  return strftime "%Y-%m-%d %X %Z (%z)", localtime($self->{_doc}{created})
    if $format;

  return $self->{_doc}{created};
}

=head2 updated

  Arg[1]:     : None
  Example     : my $updated = $trackdb->updated();
  Description : Returns the timestamp representing the time when the trackDB was last updated
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub updated {
  my ($self, $format) = @_;

  return unless $self->{_doc}{updated};

  return strftime "%Y-%m-%d %X %Z (%z)", localtime($self->{_doc}{updated})
    if $format;

  return $self->{_doc}{updated};
}

=head2 source

  Arg[1]:     : None
  Example     : my $source = $trackdb->source();
  Description : Returns the structure representing the remote source file of the trackDB
  Returntype  : HashRef
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub source {
  return shift->{_doc}{source};
}

=head2 compute_checksum

  Arg[1]:     : None
  Example     : my $checksum = $trackdb->checksum();
  Description : Compute the checksum of the remote source trackDB file
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub compute_checksum {
  my $self = shift;
  
  my $source_url = $self->{_doc}{source}{url};
  defined $source_url or die sprintf "Cannot get source URL for trackDb %s", $self->id;

  return Registry::Utils::checksum_compute($source_url);
}

=head2 assembly

  Arg[1]:     : None
  Example     : my $assembly = $trackdb->assembly();
  Description : Returns the structure representing trackDB assembly data
  Returntype  : HashRef
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub assembly {
  return shift->{_doc}{assembly};
}

=head2 status

  Arg[1]:     : None
  Example     : my $status = $trackdb->status();
  Description : Returns the structure representing trackDB status data
  Returntype  : HashRef
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub status {
  my $self = shift;
  
  return $self->{_doc}{status};
}

=head2 status_message

  Arg[1]:     : None
  Example     : my $msg = $trackdb->status_message();
  Description : Returns the message representing the status of the remote trackDB
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub status_message {
  my $self = shift;

  return $self->{_doc}{status}{message};
}

=head2 status_last_update

  Arg[1]:     : None
  Example     : my $last_update = $trackdb->status_last_update();
  Description : Returns the timestamp reprenting when the status of the trackDB was last checked
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub status_last_update {
  my ($self, $format) = @_;

  return unless $self->{_doc}{status}{last_update};

  return strftime "%x %X %Z (%z)", localtime($self->{_doc}{status}{last_update})
    if $format;

  return $self->{_doc}{status}{last_update};
}

=head2 toggle_search

  Arg[1]:     : None
  Example     : $trackdb->toggle_search();
  Description : Enable/disable search for this trackDB from the front-end
  Returntype  : None
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub toggle_search {
  my $self = shift;

  my $doc = $self->{_doc};
  $doc->{public} = $doc->{public}?0:1;

  $self->{_es}{client}->index(index  => $self->{_es}{index},
			      type   => $self->{_es}{type},
			      id     => $self->{_id},
			      body   => $doc);
  $self->{_es}{client}->indices->refresh(index => $self->{_es}{index});
}

=head2 update_status

  Arg[1]:     : None
  Example     : my $status = $trackdb->update_status();
  Description : Update the status of the trackDB, internally it checks whether
                all remote data files pointed to by the tracks are remotely available
  Returntype  : HashRef - the updated status data structure
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

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

  # should not do this as now there's only one process 
  # checking the trackDBs
  # die sprintf "TrackDB document [%s] is already being checked by another process.", $self->{_id}
  #   if $doc->{status}{message} eq 'Pending';
    
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
	  # # handle compressed formats
	  # $index = -2 if $path[-1] eq 'gz';
	  $self->{_doc}{file_type}{$format_lookup{$path[$index]}}++;
	}

      }
    }
  }
  
}

1;
