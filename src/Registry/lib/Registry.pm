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

=cut

package Registry;
use Moose;
use namespace::autoclean;
use Log::Log4perl::Catalyst;

use Catalyst::Runtime 5.80;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

    # Session
    # Session::State::Cookie
    # Session::Store::FastMmap
use Catalyst qw/
    -Debug
    ConfigLoader
    Static::Simple
    StackTrace
    +CatalystX::SimpleLogin
    Authentication
    Authorization::Roles
    Session
    Session::Store::FastMmap
    Session::State::Cookie
/;

extends 'Catalyst';

our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in registry.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

# TIP: Here is a short script that will dump the contents of MyApp-config> to Config::General format in myapp.conf:

#     $ CATALYST_DEBUG=0 perl -Ilib -e 'use MyApp; use Config::General;
#         Config::General->new->save_file("myapp.conf", MyApp->config);'

__PACKAGE__->config(
		    name => 'Registry',
		    # Disable deprecated behavior needed by old applications
		    disable_component_resolution_regex_fallback => 1,
		    enable_catalyst_header => 1, # Send X-Catalyst header
		    'Plugin::ConfigLoader' => #Allow key = [val] to become an array
		    { 
		     driver => { General => { -ForceArray => 1}, },
		    },
		    'Plugin::Session' => 
		    {
		     flash_to_stash => 1
		    },
		    'Controller::Login' => 
		    {
		     traits => ['-RenderAsTTTemplate'],
		    },
		    'Plugin::Static::Simple' => 
		    {
		     ignore_extensions => [ qw/tmpl tt tt2 xhtml/ ],
		    },
		    # # the model (to index and search)
		    # 'Model::Search' => 
		    # {
		    #  nodes           => 'localhost:9200',
		    #  request_timeout => 30,
		    #  max_requests    => 10_000,
		    #  index           => 'test',
		    #  type            => {
		    # 			 trackhub => 'trackhub',
		    # 			 user     => 'user'
		    # 			}
		    # },
		    # # API authentication
		    # # Auth with HTTP (basic or digest) credential and Elasticsearch store
		    # 'Plugin::Authentication' => 
		    # {
		    #  default_realm => 'testweb',
		    #  realms => {
		    # 		testweb => {
		    # 			 credential => {
		    # 					class => 'Password',
		    # 					password_field => 'password',
		    # 					password_type  => 'clear',
		    # 				       },
		    # 			 store => {
		    # 				   class => 'ElasticSearch',
		    # 				   index => 'test',
		    # 				   type  => 'user'
		    # 				  }
		    # 			},
		    # 		testhttp => {
		    # 			 credential => {
		    # 					class => 'HTTP',
		    # 					type  => 'basic', # 'digest'|'basic|'any'
		    # 					password_type  => 'clear',
		    # 					password_field => 'password'
		    # 				       },
		    # 			 store => {
		    # 				   class => 'ElasticSearch',
		    # 				   index => 'test',
		    # 				   type  => 'user'
		    # 				  }
		    # 			},
		    # 		testauthkey => {
		    # 			 credential => {
		    # 					class => 'Password',
		    # 					# No password check is done.  An attempt is made to retrieve the user 
		    # 					# based on the information provided in the $c->authenticate() call. 
		    # 					# If a user is found, authentication is considered to be successful.
		    # 					#
		    # 					# NOTE
		    # 					# This is actually not working in combination with a Minimal store,
		    # 					# since this store is just using the username information to locate a
		    # 					# a user and not any other provided piece of info (e.g. auth_key).
		    # 					# The result is that the user will always be authenticated if we just
		    # 					# provide an existing user id.
		    # 					#
		    # 					password_type  => 'none' 
		    # 				       },
		    # 			 store => {
		    # 				   class => 'ElasticSearch',
		    # 				   index => 'test',
		    # 				   type  => 'user'
		    # 				  }
		    # 			},
		    # 	       }
		    # },
		   );

# Start the application
my $log4perl_conf = $ENV{REGISTRY_LOG4PERL} || 'log4perl.conf';
if(-f $log4perl_conf) {
  __PACKAGE__->log(Log::Log4perl::Catalyst->new($log4perl_conf));
} else {
  __PACKAGE__->log(Log::Log4perl::Catalyst->new());
}
__PACKAGE__->setup();

=encoding utf8

=head1 NAME

Registry - Catalyst based application

=head1 SYNOPSIS

    script/registry_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<Registry::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Alessandro,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
