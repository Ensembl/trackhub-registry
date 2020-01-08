#!/usr/bin/env perl
# Copyright [2015-2020] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use Catalyst::ScriptRunner;
Catalyst::ScriptRunner->run('Registry', 'FastCGI');

1;

=head1 NAME

registry_fastcgi.pl - Catalyst FastCGI

=head1 SYNOPSIS

registry_fastcgi.pl [options]

 Options:
   -? --help      display this help and exit
   -l --listen   socket path to listen on
                 (defaults to standard input)
                 can be HOST:PORT, :PORT or a
                 filesystem path
   -n --nproc    specify number of processes to keep
                 to serve requests (defaults to 1,
                 requires --listen)
   -p --pidfile  specify filename for pid file
                 (requires --listen)
   -d --daemon   daemonize (requires --listen)
   -M --manager  specify alternate process manager
                 (FCGI::ProcManager sub-class)
                 or empty string to disable
   -e --keeperr  send error messages to STDOUT, not
                 to the webserver
   --proc_title  Set the process title (if possible)

=head1 DESCRIPTION

Run a Catalyst application as FastCGI.

=head1 AUTHORS

Catalyst Contributors, see Catalyst.pm

=head1 COPYRIGHT

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
