=head1 LICENSE

Copyright [2015-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Registry::User::DB;

use Moose;
use DBI;
use Carp;
use Digest::SHA1 qw(sha1);
use Config::General;
use Registry::User::Schema;

has dsn => (
  is => 'ro',
  isa => 'Str',
);

has dbuser => (
  is => 'ro',
  isa => 'Str',
);

has dbpass => (
  is => 'ro',
  isa => 'Str',
);

has schema => (
  isa => 'Registry::User::Schema',
  is => 'ro',
  builder => '_init_db',
  lazy => 1
);

has config => (
  isa => 'HashRef',
  is => 'rw',
  required => 1
);

# Used for multiple SQL dialect support, see also SQLite
has now_function => (
  isa => 'Str',
  default => 'now()',
  is => 'rw',
);

=head2 _init_db
  Arg [1]    : HashRef of configuation parameters (driver, db, host, port, user, pass)
  Description: Initialise a user database.
  Return type: Registry::User::Schema
  Caller     : internal
=cut

sub _init_db {
  my $self = shift;

  $self->_validate_config($self->config);
  my %conf = %{ $self->config };
  my %opts;
  my $dsn;

  if ($conf{driver} eq 'mysql') {
    $opts{mysql_enable_utf8}    = 1;
    $opts{mysql_auto_reconnect} = 1;
    $dsn = sprintf 'dbi:%s:database=%s;host=%s;port=%s', $conf{driver}, $conf{db}, $conf{host}, $conf{port};
  } elsif ($conf{driver} eq 'SQLite') {
    $opts{sqlite_unicode} = 1;
    $dsn = sprintf 'dbi:%s:database=%s',$conf{driver},$conf{file};
    $self->now_function("date('now')");
  } else {
    confess 'Invalid driver specified in conf: '.$conf{driver};
  }
  $self->{dsn} = $dsn;
  my %deploy_opts = ();
  # Example deploy option $deploy_opts{add_drop_table} = 1;
  my $schema = Registry::User::Schema->connect($dsn, $conf{user}, $conf{pass}, \%opts);

  if (exists $conf{create} && $conf{create} == 1 && $conf{driver} eq 'mysql') {
    my $dbh = DBI->connect(
      $dsn,
      $conf{user},
      $conf{pass},
      \%opts
    );

    # Remove database if already exists
    my %dbs = map {$_->[0] => 1} @{$dbh->selectall_arrayref('SHOW DATABASES')};
    my $dbname = $conf{db};
    if ($dbs{$dbname}) {
      $dbh->do( "DROP DATABASE $dbname;" );
    }

    $dbh->do( "CREATE DATABASE $dbname;" );

    $dbh->disconnect;
  }

  if ( exists $conf{create} && $conf{create} == 1 ) {
    $schema->deploy(\%deploy_opts);
    $schema->resultset( 'Role' )->populate( [
      [ 'name' ],
      [ 'user' ],
      [ 'admin' ],
    ] );
  }

  return $schema;
} ## end sub _init_db

=head2 _validate_config
  Arg [1]    : HashRef of configuation parameters (driver, db, host, port, user, pass)
  Description: Configuration file parameter validation
  Return type: DBI database handle
  Caller     : internal
=cut

sub _validate_config {
  my ($self,$config) = @_;
  my @required_keys = qw/driver/;
  if ($config->{driver} eq 'mysql') {
    push @required_keys, qw/db host port user pass/;
  } elsif ($config->{driver} eq 'SQLite') {
    push @required_keys, qw/file/;
  } else {
    confess q(DB config requires parameter 'driver' with value mysql or SQLite);
  }
  my @errors;
  foreach my $constraint (@required_keys) {
    if (! exists $config->{$constraint}) {
      push @errors, "Missing argument '$constraint'";
    }
  }
  if (scalar @errors > 0) {
    confess sprintf "Missing options in config:\n%s", ,
      join ';',@errors;
  }
} ## end sub _validate_config

__PACKAGE__->meta->make_immutable;

1;