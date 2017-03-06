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

Registry::TrackHub::Validator - Validate trackDB jSON document

=head1 SYNOPSIS

my $validator = Registry::TrackHub::Validator->new(schema => 'path to schema file');

try {
  $validator->validate($trackdb_json_file);  
} catch {
  warn "Could not validate JSON at $trackdb_json_file";
};

=head1 DESCRIPTION

A class providing a method to validate JSON according to a given schema.

=head1 AUTHOR

Alessandro Vullo, C<< <avullo at ebi.ac.uk> >>

=head1 BUGS

No known bugs at the moment. Development in progress.

=cut

package Registry::TrackHub::Validator;

use strict;
use warnings;

use Capture::Tiny qw( capture );
use File::Basename qw();

use vars qw($AUTOLOAD);

sub AUTOLOAD {
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  $self->{$attr} = shift if @_;

  return $self->{$attr};
}

=head1 METHODS

=head2 new

  Arg[1]:     : Hash - constructor parameters
                       schema - String - filename of the JSON schema
  Example     : Registry::TrackHub::Validator->new(schema => '/path/to/schema/file.json');
  Description : Build a Registry::TrackHub::Validator object
  Returntype  : Registry::TrackHub::Validator
  Exceptions  : Thrown if required parameter is not provided or schema file is not readable
  Caller      : Registry::Controller::API::Registration
  Status      : Stable

=cut

sub new {
  my ($class, %args) = @_;

  defined $args{schema} or die "Undefined JSON schema";
  -e $args{schema} and -f $args{schema} or
    die "Unable to read schema file: $args{schema}";

  my $self = \%args;
  bless $self, $class;

  return $self;
}

=head2 validate

  Arg [1]     : String - filename containing JSON to validate
  Example:    : print "OK" if $validator->validate('/path/to/json/file');
  Description : Validates the given JSON file according to the given schema
  Returntype  : Scalar - true value if JSON validates
  Exceptions  : Thrown if cannot validate or some other error occurs
  Caller      : Registry::Controller::API::Registration
  Status      : Stable

=cut

sub validate {
  my ($self, $file) = @_;

  my $cfile = __FILE__;
  my ($name, $path, $suffix) = File::Basename::fileparse($cfile);
  my $cmd = sprintf("$path/../../../../../docs/trackhub-schema/validate.py -s %s -f %s", $self->{schema}, $file);
  # my ($rc, $output) = Registry::Utils::run_cmd($cmd);
  my ($output, $err, $rc) = capture { system( $cmd ); };
  
  # Handle here the unexpected, the python validation script cannot run,
  # e.g. the schema is badly formatted
  if ($rc) {
    # this is to handle errors of the Python script
    # which cannot decode some UTF characters
    # WARNING: we get 256 in other circumnstances too, i.e. imported modules are not installed
    #          so here we assume jsonschema (validate script dependency) is installed and on
    #          the python module search path
    return 0 if $rc == 256 and $err !~ /ImportError/s;

    die "Command \"$cmd\" failed $!\n" if $rc == -1;
    die "Command \"$cmd\" exited with value $rc\n$output\n";
  }

  # insert here whatever condition on the output 
  # is interpreted to be a failure
  #
  # better to raise an exception, so we can emit an output
  # which indeed is interesting only if the doc does not validate
  # the caller decides what to do, stop or continue
  #
  # At the moment, the validation script simply prints the errors,
  # if there's any.
  if ($output || $err) {
    # the validation script prepend the JSON instance
    # to the error output.
    # remove
    $output =~ s/^.+?(?=Failed.+?)//s;
    die $output;
  }

  # success
  return 1;
}

1;
