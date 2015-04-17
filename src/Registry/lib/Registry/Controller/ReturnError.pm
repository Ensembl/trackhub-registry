package Registry::Controller::ReturnError;
use Moose;
use namespace::autoclean;
use Carp::Clan qw(^Registry::Controller::);
BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    'default'   => 'application/json',
#     'stash_key' => 'rest',
    'map'       => {
        'text/x-yaml'       => 'YAML::XS',
        'application/json'  => 'JSON::XS',
        'text/plain'        => 'JSON::XS',
        'text/html'         => 'YAML::HTML',
    }
);

sub index : Path : Args(0) : ActionClass('REST') {
    my ( $self, $c, $raw_error ) = @_;

    $c->log->error($raw_error);


    #     #     $error =~ s/\n/\\x/g;
    #     $error = "thist!";
    #     $error =~ s/s/\n/g;
    #     $c->log->warn( 'ERROR: ', $error );
    # my $raw_msg = $c->stash->{error};
    my ($error_cleaned) = $raw_error =~ m/MSG:\s(.*?)STACK/s;
    $error_cleaned ||= 'something bad has happened';
    $error_cleaned =~ s/\n//g;
    $self->status_bad_request( $c, message => $error_cleaned );
}

sub index_GET { }
sub index_POST { }

sub custom : Path : Args(0) : ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $c->log->error($error_msg);
    
  $self->status_bad_request( $c, message => $error_msg );
}

sub custom_GET { }
sub custom_POST { }
sub custom_PUT { }

sub no_content: Path : Args(0) : ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $c->log->error($error_msg);
  $self->status_no_content( $c, message => $error_msg );
}

sub no_content_GET { }
sub no_content_POST { }

sub not_found: Path : Args(0) : ActionClass('REST') {
  my ( $self, $c, $error_msg ) = @_;
  $self->status_not_found($c, message => $error_msg);
}

sub not_found_GET { }
sub not_found_POST { }

__PACKAGE__->meta->make_immutable;

1;
