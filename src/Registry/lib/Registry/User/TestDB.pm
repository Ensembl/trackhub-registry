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

package Registry::User::TestDB;

use Moose;
use namespace::autoclean;

extends 'Registry::User::DB';

has reuse => (
  isa => 'Bool',
  is => 'ro',
  default => 0,
);

# On top of default config validator, inject a randomised test DB name
around '_init_db' => sub {
  my ($sub, $self, @args) = @_;
  my $config = $self->config;
  if (! exists $self->config->{db}) {
    $config->{db} = sprintf '%s_thr_user_test_%s',$ENV{USER},int(rand(100000));
    $config->{create} = 1;
  }
  $self->config($config);
  return $self->$sub(@args);
};


=head2 DEMOLISH
Description: It's a destructor. It cleans up databases left behind by the test
             Behaviour is overridden with $self->reuse(1)
=cut
sub DEMOLISH {
  my $self = shift;
  if ($self->reuse == 0 && defined $self->config) {
    if ( $self->config->{driver} eq 'SQLite') {
      unlink $self->config->{file};
    } elsif ($self->config->{driver} eq 'mysql') {
      $self->schema->storage->dbh->do('drop database '.$self->config->{db});
    }
  }
  return;
}

__PACKAGE__->meta->make_immutable;

1;