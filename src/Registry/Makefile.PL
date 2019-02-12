#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use strict;
use inc::Module::Install 1.02;
use Module::Install::Catalyst; # Complain loudly if you don't have
                               # Catalyst::Devel installed or haven't said
                               # 'make dist' to create a standalone tarball.

name 'Registry';
all_from 'lib/Registry.pm';

requires 'Catalyst::Runtime';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Plugin::StackTrace';
requires 'Catalyst::Action::RenderView';
requires 'Catalyst::View::TT';
requires 'Catalyst::View::JSON';
requires 'Log::Log4perl::Catalyst';

# for authentication/session handlng, as per
# http://www.catalystframework.org/calendar/2007/5
requires 'Catalyst::Plugin::Authentication';
requires 'Catalyst::Plugin::Authorization::Roles';
requires 'Catalyst::Authentication::Store::DBIx::Class';
requires 'Catalyst::Plugin::Session';
requires 'Catalyst::Plugin::Session::State::Cookie';
requires 'Catalyst::Plugin::Session::Store::FastMmap';
requires 'Catalyst::Plugin::StatusMessage';
requires 'CatalystX::SimpleLogin';
requires 'Catalyst::Controller::ActionRole';
requires 'Catalyst::ActionRole::ACL';
requires 'Module::Install::Catalyst';
requires 'Test::WWW::Mechanize::Catalyst';

requires 'Moose';
requires 'MooseX::NonMoose';
requires 'namespace::autoclean';
requires 'Config::General'; # This should reflect the config file format you've chosen
                 # See Catalyst::Plugin::ConfigLoader for supported formats

# for handling profile and registration forms
requires 'HTML::FormHandler::Moose';

requires 'Try::Tiny';
requires 'Capture::Tiny';
requires 'Digest::MD5';
requires 'File::Temp';
requires 'File::Spec';
requires 'List::Util';
requires 'String::Random';
requires 'Search::Elasticsearch' => '5.02'; # v6 release does not seem to work quite right
requires 'DRTECH/Search-Elasticsearch-Client-5_0-6.00.tar.gz'; # Make sure we get the v6 scroll API client for the v5 library
requires 'Clone';
requires 'Data::SearchEngine';
requires 'Encode';
requires 'HTML::Restrict';
requires 'Params::Validate';
requires 'Template';

# for file utils
requires 'Compress::Zlib';
requires 'Compress::Bzip2';
requires 'IO::Uncompress::Bunzip2';

# For accessing the Genome Collection Assemby database
requires 'Math::Base36';
requires 'DBI';
requires 'DBIx::Class';
requires 'Catalyst::Model::DBIC::Schema';
requires 'DBIx::Class::Cursor::Cached';

# for production
recommends 'Log::Log4perl';
recommends 'Log::Dispatch::Screen';
recommends 'Getopt::Long';
recommends 'Pod::Usage';
recommends 'DBM::Deep';
recommends 'Email::Date';
recommends 'DateTime';
recommends 'Scalar::Util';
recommends 'HTML::DOM';
recommends 'LWP::Protocol::https';
recommends 'Server::Starter';
recommends 'Net::CIDR::Lite';
recommends 'Net::Server::SS::PreFork';
recommends 'Cache::Memcached';
recommends 'Cache::FastMmap';
recommends 'Plack::Middleware::ReverseProxy';
recommends 'Plack::Middleware::CrossOrigin';
recommends 'Plack::Middleware::SizeLimit';
recommends 'Plack::Middleware::StackTrace';
recommends 'Plack::Middleware::Runtime';
recommends 'Plack::Middleware::ContentLength';
recommends 'Plack::Middleware::Deflater';
recommends 'Plack::Middleware::Assets';
recommends 'Plack::Middleware::Static';
recommends 'CHI::Driver::Memcached';
recommends 'Term::Size::Any';
recommends 'WWW::Mechanize';
recommends 'Proc::ProcessTable';
recommends 'WWW::Form::UrlEncoded';
recommends 'Daemon::Control';


test_requires 'Test::More';
test_requires 'Email::MIME';
test_requires 'Email::Sender::Simple';
test_requires 'Test::Deep';

catalyst;

install_script glob('script/*.pl');
auto_install;
WriteAll;
