=head1 LICENSE

Copyright [2015-2022] EMBL-European Bioinformatics Institute

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

Registry - The Catalyst Application main module

=head1 SYNOPSIS

    script/registry_server.pl

=head1 DESCRIPTION

This is the main module for the Trackhub Registry web application.
It's setting up the application at start-up either using the configuration
parameters described here or overrding them by reading from the
configuration file.

=cut

package Registry;
use Moose;
use namespace::autoclean;
use Log::Log4perl::Catalyst;

use Catalyst::Runtime;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory, or as defined by REGISTRY_CONFIG
#                 environment variable
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
    ConfigLoader
    Static::Simple
    StackTrace
    Authentication
    Authorization::Roles
    Session
    Session::Store::FastMmap
    Session::State::Cookie
    Cache
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

# TIP: Here is a short script that will dump the contents of MyApp->config
# to Config::General format in myapp.conf:

#     $ CATALYST_DEBUG=0 perl -Ilib -e 'use MyApp; use Config::General;
#         Config::General->new->save_file("myapp.conf", MyApp->config);'

__PACKAGE__->config(
    name => 'Registry',
    # Disable deprecated behaviour needed by old applications
    disable_component_resolution_regex_fallback => 1,
    'Plugin::ConfigLoader' => { 
        driver => { 
            General => { 
                -ForceArray => 1 #Allow key = [val] to become an array
            }, 
        },
    },
    'Plugin::Session' => {
        flash_to_stash => 1
    },
    'Plugin::Static::Simple' => {
        ignore_extensions => [ qw/tmpl tt tt2 xhtml/ ],
    }
);

# Start the application
my $log4perl_conf = $ENV{REGISTRY_LOG4PERL} || 'log4perl.conf';
if(-f $log4perl_conf) {
  __PACKAGE__->log(Log::Log4perl::Catalyst->new($log4perl_conf));
} else {
  __PACKAGE__->log(Log::Log4perl::Catalyst->new());
}
__PACKAGE__->setup();

1;
