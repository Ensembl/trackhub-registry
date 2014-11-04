package ElasticSearchDemo::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=encoding utf-8

=head1 NAME

ElasticSearchDemo::Controller::Root - Root Controller for ElasticSearchDemo

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut

sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  # Hello World
  # $c->response->body( $c->welcome_message );

  # Display the search form
  $c->stash(template => 'search_form.tt')
}

=head2 default

Standard 404 error page

=cut

sub default :Path {
    my ( $self, $c ) = @_;
    $c->response->body( 'Page not found' );
    $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head2 search

Perform a search

=cut 

# DEPRECATION WARNING: The Regex dispatch type is deprecated.
#   The standalone Catalyst::DispatchType::Regex distribution
#   has been temporarily included as a prerequisite of
#   Catalyst::Runtime, but will be dropped in the future. Convert
#   to Chained methods or include Catalyst::DispatchType::Regex
#   as a prerequisite for your application.
#
# Something like this?
# handles /search?q=...
# sub search : Chained('/') :PathPart('search') :Args(0) { # Args ends the chain, is zero because args are passed as GET parameters
#
# handles /search/:index/:type/?q=...
sub search : Chained('/') :PathPart('search') :Args(2) { 
# see https://metacpan.org/pod/Catalyst::Manual::Tutorial::04_BasicCRUD
#
# sub search :Regex('^search$') { # :Local  {
  my ($self, $c, $index, $type) = @_;
  $index ||= 'test';
  $type ||= 'trackhub';
  my $params = $c->req->params;
  my $query = $params->{'q'};
  my $search = $c->model('ElasticSearch');
  my $results = $search->search(index => $index,
				type  => $type,
				# body  => { query => { term => { alignment_software => $params->{'q'} } } }, # term filter: exact value
				# http://www.elasticsearch.org/guide/en/elasticsearch/guide/current/_finding_exact_values.html
				# The term filter isn’t very useful on its own though. As discussed in Query DSL, the search API 
				# expects a query, not a filter. To use our term filter, we need to wrap it with a filtered query:
				# body  => { 
				# query => {
				# 	    "filtered" => { 
				# 			   query => { "match_all" => {} }, # returns all documents (default, can omit)
				# 			   filter => { term => { _all => $params->{'q'} } }
				# 			   }
				# 	    }
				# },									       
				body  => { query => { match => { _all => $params->{'q'} } } } # match query: full text search
			       );

  $c->stash(index => $index);
  $c->stash(type => $type);
  $c->stash(results => $results);
  $c->stash(template => 'search_results.tt')

}

=head2 login

=cut

sub login :Path('/api/login') Args(0) {
  my ($self, $c) = @_;

  $c->authenticate;

  # user should exist
  $c->user->auth_key(String::Random::random_string('s' x 64));
  # $c->user->obj->update();
  # $c->response->headers->header('x-registry-authorization' => $c->user->get('auth_key'));
  
  # $self->status_ok($c, entity => { auth_token => $c->user->get('auth_key') });
  $c->stash()->{auth_token} = $c->user->get('auth_key');
  $c->forward($c->view('JSON'));
}

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
