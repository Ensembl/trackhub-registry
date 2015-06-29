#
# The backing user class for the Catalyst::Authentication::Store::ElasticSearch storage module.
#
package Catalyst::Authentication::Store::ElasticSearch::User;

use strict;
use warnings;

BEGIN {
  $Catalyst::Authentication::Store::ElasticSearch::User::VERSION = '0.001';
}

use Moose 2.000;
use MooseX::NonMoose 0.20;
use Catalyst::Exception;
use Catalyst::Utils;

use LWP;
use JSON 2.17 qw ();
use Try::Tiny 0.09;
use Search::Elasticsearch;

use namespace::autoclean;
extends 'Catalyst::Authentication::User';

has '_user'  => (is => 'rw', isa => 'HashRef', );
has '_es'    => (is => 'ro', isa => 'Search::Elasticsearch::Client::Direct', );
has '_index' => (is => 'ro', isa => 'Str', required => 1, );
has '_type'  => (is => 'ro', isa => 'Str', required => 1, );

around BUILDARGS => sub {
  my ($orig, $class, $config, $c) = @_;

  Catalyst::Exception->throw("Elasticsearch nodes required in configuration")
      unless $config->{nodes};

  # Catalyst::Exception->throw("Elasticsearch transport required in configuration")
  #     unless $config->{transport};
    
  my $es = 
    Search::Elasticsearch->new(nodes     => $config->{nodes}); # transport => $config->{transport});
 
  # test connection
  #
  # TODO
  # should consider nodes can be an array
  #
  my $url = $config->{nodes};
  $url = "http://$url" unless $url =~ /^http/;
  my $req = HTTP::Request->new( GET => $url );
  my $ua = LWP::UserAgent->new;
  my $response = $ua->request($req);
  Catalyst::Exception->throw("Elasticsearch instance not available")
      unless $response->is_success;

  # test the index exists
  Catalyst::Exception->throw("index name required in configuration")
      unless $config->{index};

  $es->indices->exists(index => $config->{index})
    or Catalyst::Exception->throw("Index does not exist");

  # test type exists
  Catalyst::Exception->throw("user type required in configuration")
      unless $config->{type};

  $es->indices->exists_type(index => $config->{index},
			    type  => $config->{type})
    or Catalyst::Exception->throw("Type does not exist");

  return $class->$orig(_es    => $es,
		       _index => $config->{index},
		       _type  => $config->{type});
};


sub load {
  my ($self, $authinfo, $c) = @_;

  my $query = { bool => { must => [] } };
  foreach my $key (keys %{$authinfo}) {
    push @{$query->{bool}{must}}, { term => { $key =>  $authinfo->{$key} } };
  }

  my $user_search = $self->_es->search(index => $self->_index,
				       type  => $self->_type,
				       # # term filter: exact value
				       # body  => { query => { term => { username => $username } } });
				       body => { query => $query });

  return unless $user_search;
  # no user found
  return unless $user_search->{hits}{total};
  # multiple users found
  Catalyst::Exception->throw("Multiple users found")
      if $user_search->{hits}{total} > 1;

  return unless ref $user_search->{hits}{hits} eq 'ARRAY';
  
  $self->_user($user_search->{hits}{hits}[0]);
  return $self;
}

sub supported_features {
  my $self = shift;

  return {
	  session => 1,
	  roles   => 1,
	 };
}

sub id {
  my ($self) = @_;
  return $self->_user->{_id};
}


sub roles {
  my ($self) = shift;

  return @{$self->_user->{_source}{roles}};
}

sub get {
  my ($self, $field) = @_;

  return unless defined $self->_user;

  return $self->id if $field eq 'id';

  return $self->_user->{_source}{$field}
    if exists $self->_user->{_source}{$field};  
  
  return;
}

sub delete {
  my ($self, $field) = @_;

  return unless defined $self->_user;

  delete $self->_user->{_source}{$field};

  # reindex/refresh user to persist change
  $self->_es->index(index => $self->_index,
		    type  => $self->_type,
		    id    => $self->id,
		    body  => $self->_user->{_source});
  $self->_es->indices->refresh(index => $self->_index);

  return;
}

sub get_object {
  my ($self, $force) = @_;

  return $self->_user;
}

sub for_session {
  my ($self) = @_;

  # Return JSON here, because it's fast, it's human readable so we can
  # see what's going on in the session.  We can't return the data structure,
  # because something in the session handling somewhere is mangling it.
  return JSON::encode_json($self->_user);
}

sub from_session {
  my ($self, $frozen_user) = @_;

  $self->_user(JSON::decode_json($frozen_user));
  return $self;
}

# sub AUTOLOAD {
#   my ($self) = @_;

#   (my $method) = (our $AUTOLOAD =~ /([^:]+)$/);
#   return if $method eq "DESTROY";

#   return $self->get($method);
# }

sub AUTOLOAD {
  my $self = shift;
  our $AUTOLOAD;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;

  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods

  if (@_) {
    $self->_user->{_source}{$attr} = shift;
    
    # update (i.e. reindex) the whole doc with the new attribute
    $self->_es->index(index => $self->_index,
		      type  => $self->_type,
		      id    => $self->id,
		      body  => $self->_user->{_source});

    # refresh is needed to immediately see the change
    $self->_es->indices->refresh(index => $self->_index);  
  } 
  
  return $self->get($attr);
  
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;




=pod

=head1 NAME

Catalyst::Authentication::Store::ElasticSearch::User - The backing user class for the Catalyst::Authentication::Store::ElasticSearch storage module.

=head1 VERSION

version 0.001

=head1 DESCRIPTION

The L<Catalyst::Authentication::Store::ElasticSearch:User> class
implements user storage connected to a ElasticSearch instance.

=head1 SYNPOSIS

Internal - not used directly.

=head1 METHODS

=head2 new

Constructor.  Connects to the ElasticSearch instance in the configuration, and
fetches the design document that contains the configured view.

=head2 load ( $authinfo, $c )

Retrieves a user from storage.  It queries the configured view, and converts
the first document retrieved into a ElasticSearch document.  This is then used
as the User backing object

=head2 supported_features

Indicates the features supported by this class.

=head2 roles

Returns a list of roles supported by this class.  These are stored as an array
in the 'roles' field of the User document.

=head2 for_session

Returns a serialised user for storage in the session.  This is a JSON
representation of the user.

=head2 from_session ( $frozen_user )

Given the results of for_session, deserialises the user, and recreates the backing
object.

=head2 get ( $fieldname )

Returns the field $fielname from the backing object.

=head2 AUTOLOAD

AUTOLOAD is defined so that calls to missing methods will get converted into a call to
C<get> for the field matching the method name.  This is convenient for use inside templates,
as for example C<user.name> will now return the C<name> field from the user document.

=head1 NOTES

This module is heavily based on L<Catalyst::Authentication::Store::DBIx::Class::User>.

=head1 BUGS

None known, but there are bound to be some.  Please email the author.

=head1 AUTHOR

Colin Bradford <cjbradford@gmail.com>

=head1 COPYRIGHT AND LICENSE

=cut


__END__

