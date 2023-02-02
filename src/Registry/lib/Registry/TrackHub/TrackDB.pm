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

Registry::TrackHub::TrackDB - Interface to a trackDB JSON document

=head1 SYNOPSIS

my $trackdb = Registry::TrackHub::TrackDB->new(doc => $hashref);
print $trackdb->status_last_update;
my $content = $trackdb->doc;

=head1 DESCRIPTION

A class to represent track db data in JSON format, to provide methods to get/set informantion,
check and update the status of its tracks. An object of this class is built from an ElasticSearch 
document.

Typically used to carry hub information to template toolkit, like a Java Bean.
Template Toolkit CANNOT understand hashrefs and objects in the same call, and requires accessors.

This object type is not used to modify data before saving. It could do with enabling with
serialisation ability.

=cut

package Registry::TrackHub::TrackDB;

use Moose;
use POSIX qw(strftime);

use Registry::Utils;
use Registry::Utils::Exception;

# Received a complex document as hashref, populate the relevant attributes of this class
sub BUILD {
  my ($self, $args) = @_;
  if (exists $args->{doc}) {

    foreach my $field (qw/type hub version source assembly status public/) {
      if (exists $args->{doc}{$field}) {
        $self->$field( $args->{doc}{$field});
      }
    }
    $self->file_type([ sort keys %{ $args->{doc}{file_type} } ]);
    if (exists $args->{doc}{created}) {
      $self->created_time( $args->{doc}{created} );
    }
    if (exists $args->{doc}{updated}) {
      $self->updated_time( $args->{doc}{updated} );
    }

  } else {
    # gonna be a useless TrackDB without a doc argument, but maybe you want to interfere?
    Registry::Utils::Exception->throw('Please supply a hashref converted from a trackhub JSON document');
  }
  return $self;
}

has doc => (
  is => 'rw',
  isa => 'HashRef',
  documentation => 'The HashRef form of the document from Elasticsearch'
);

has id => (
  is => 'rw',
  isa => 'Str',
  documentation => 'The UUID assigned by ElasticSearch',
);

has type => (
  is => 'rw',
  isa => 'Str',
  documentation => 'Refers to the type of data in a genomics sense',
  default => 'genomics'
);

has hub => (
  traits => ['Hash'],
  is => 'rw',
  isa => 'HashRef',
  documentation => 'The hub portion of the trackDB document as hashref',
  handles => {
    hub_property => 'get'
  }
);

has version => (
  is => 'rw',
  isa => 'Str',
  documentation => 'The JSON schema version that applies to the document'
);

has file_type => (
  is => 'rw',
  isa => 'ArrayRef[Str]',
  documentation => 'A list of file types present in the hub'
);

has created_time => (
  is => 'rw',
  isa => 'Int',
  documentation => 'The time (unix epoch) that the hub was created'
);

has updated_time => (
  is => 'rw',
  isa => 'Maybe[Int]',
  documentation => 'The time (unix epoch) that the hub was last updated'
);

has source => (
  is => 'rw',
  isa => 'HashRef',
  documentation => 'Information about the source of the hub'
);

has assembly => (
  is => 'rw',
  isa => 'HashRef',
  documentation => 'Assembly information from the hub'
);

has status => (
  traits => ['Hash'],
  is => 'rw',
  isa => 'HashRef',
  documentation => 'Status information relating to the accessibility of the backing data URLs',
  handles => {
    status_property => 'get'
  }
);

has public => (
  is => 'rw',
  isa => 'Bool',
  documentation => 'Whether the hub is publicly findable or not, boolean true/false'
);

=head1 METHODS

=head2 created

  Arg[1]:     : Boolean, choose whether to ISO format the time of creation
  Example     : my $created = $trackdb->created();
  Description : Returns the timestamp representing the time when the trackDB was initially stored
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General

=cut

sub created {
  my ($self, $format) = @_;

  return unless $self->created_time;

  if ($format) {
    return strftime "%Y-%m-%d %X %Z (%z)", localtime($self->created_time)
  } else {
    return $self->created_time;
  }
}

sub assembly_name { return shift->assembly->{name} }
sub hub_name { return shift->hub->{name} }
sub version_number { return shift->{version} }
sub scientific_name { return shift->{species}->{scientific_name} }

=head2 updated

  Arg[1]:     : Boolean, choose whether to ISO format the time of update
  Example     : my $updated = $trackdb->updated();
  Description : Returns the timestamp representing the time when the trackDB was last updated
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General

=cut

sub updated {
  my ($self, $format) = @_;

  return unless $self->updated_time;

  if ($format) {
    return strftime "%Y-%m-%d %X %Z (%z)", localtime($self->updated_time)
  }

  return $self->updated_time;
}

=head2 compute_checksum

  Example     : my $checksum = $trackdb->checksum();
  Description : Compute the checksum of the remote source trackDB file
  Returntype  : Scalar
  Exceptions  : On there being no source URL in the document
  Caller      : General
  Status      : Stable

=cut

sub compute_checksum {
  my $self = shift;
  
  my $source_url = $self->source->{url};
  unless (defined $source_url) {
    Registry::Utils::Exception->throw(sprintf "Cannot get source URL for trackDb %s", $self->id);
  }

  return Registry::Utils::checksum_compute($source_url);
}


=head2 status_message

  Example     : my $msg = $trackdb->status_message();
  Description : Returns the message representing the status of the remote trackDB
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General

=cut

sub status_message {
  my $self = shift;
  if ($self->status) {
    return $self->status->{message};
  }
  return;
}

=head2 status_last_update

  Arg[1]:     : Boolean, choose whether to ISO format the time since status was updated
  Example     : my $last_update = $trackdb->status_last_update();
  Description : Returns the timestamp representing when the status of the trackDB was last checked
  Returntype  : Scalar
  Exceptions  : None
  Caller      : General
  Status      : Stable

=cut

sub status_last_update {
  my ($self, $format) = @_;

  return unless $self->status && $self->status->{last_update};

  if ($format) {
    return strftime "%x %X %Z (%z)", localtime($self->status->{last_update})
  }
  return $self->status->{last_update};
}

1;
