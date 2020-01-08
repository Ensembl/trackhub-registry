=head1 LICENSE

Copyright [2015-2020] EMBL-European Bioinformatics Institute

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
use DBIx::ParseDSN;
use Carp;
use Digest::SHA1 qw(sha1);
use Config::General;
use Registry::User::Schema;
use Registry::Utils::Exception;

has dsn => (
  is => 'rw',
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

  my %conf = %{ $self->config };
  my %opts;

  if (! $self->dsn ) {
    # If a DSN is provided, then presumably you know what you're doing?
    my $dsn;
    if (lc $conf{driver} eq 'mysql') {
      $self->_validate_config($self->config, [qw/db host port user pass/]);
      $opts{mysql_enable_utf8}    = 1;
      $opts{mysql_auto_reconnect} = 1;
      $dsn = sprintf 'dbi:%s:database=%s;host=%s;port=%s', $conf{driver}, $conf{db}, $conf{host}, $conf{port};
    } elsif (lc $conf{driver} eq 'sqlite') {
      $self->_validate_config($self->config, [qw/file/]);
      $opts{sqlite_unicode} = 1;
      $dsn = sprintf 'dbi:%s:database=%s',$conf{driver},$conf{file};
      $self->now_function("date('now')");
    } else {
      confess 'Invalid driver specified in conf: '.$conf{driver};
    }
    $self->dsn($dsn);
  } else {
    # Extract db name so we can check if we need to create it
    my $dsn = parse_dsn($self->dsn);
    $conf{db} = $dsn->database;
  }

  my %deploy_opts = ();
  # Example deploy option $deploy_opts{add_drop_table} = 1;


  if (exists $conf{driver} && lc $conf{driver} eq 'mysql' && exists $conf{create} && $conf{create} == 1) {
    # Connect outside of the ORM so we can create the database
    my $dbh = DBI->connect(
      $self->dsn,
      $conf{dbuser},
      $conf{dbpass},
      \%opts
    );
    if (! defined $dbh) {
      Registry::Utils::Exception->throw('Failed to connect to '.$self->dsn. ' with provided credentials');
    }

    # Remove database if it already exists
    my %dbs = map {$_->[0] => 1} @{$dbh->selectall_arrayref('SHOW DATABASES')};
    my $dbname = $conf{db};
    if ($dbs{$dbname}) {
      $dbh->do( "DROP DATABASE $dbname;" );
    }

    $dbh->do( "CREATE DATABASE $dbname;" );

    $dbh->disconnect;
  }

  my $schema = Registry::User::Schema->connect($self->dsn, $conf{dbuser}, $conf{dbpass}, \%opts);

  if ( exists $conf{create} && $conf{create} == 1 ) {
    $schema->deploy(\%deploy_opts);
    # Put in the default roles, but leave users up to the creator of the database
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
  Arg [2]    : ListRef of keys we expect in the config
  Description: Configuration file parameter validation
  Return type: DBI database handle
  Caller     : internal
=cut

sub _validate_config {
  my ($self, $config, $required_keys) = @_;
  my @required_keys = @$required_keys;
  
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