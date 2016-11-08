use utf8;
package Registry::Schema::Result::UserToken;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Registry::Schema::Result::UserToken

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=item * L<DBIx::Class::TimeStamp>

=item * L<DBIx::Class::PassphraseColumn>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp", "PassphraseColumn");

=head1 TABLE: C<user_tokens>

=cut

__PACKAGE__->table("user_tokens");

=head1 ACCESSORS

=head2 username

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 auth_key

  data_type: 'text'
  is_nullable: 0

=head2 created_on

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "username",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "auth_key",
  { data_type => "text", is_nullable => 0 },
  "created_on",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</username>

=item * L</auth_key>

=back

=cut

__PACKAGE__->set_primary_key("username", "auth_key");

=head1 RELATIONS

=head2 username

Type: belongs_to

Related object: L<Registry::Schema::Result::User>

=cut

__PACKAGE__->belongs_to(
  "username",
  "Registry::Schema::Result::User",
  { username => "username" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07046 @ 2016-10-27 12:09:08
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:X6htzQRDojK4qZRkcw+CCA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
