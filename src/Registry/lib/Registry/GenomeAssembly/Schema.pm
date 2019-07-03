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

=head2 DESCRIPTION

A very simple DBIC schema for accessing genome assembly information hosted at
the EBI. When connected up it would allow us to dynamically extract INSDC
assembly accessions from another EBI service. For simplicity this is
historically done from a file dump of that database so that it is not reliant
on firewalls between services and networking for a critical function.

=cut

package Registry::GenomeAssembly::Schema;

use strict;
use warnings;
use utf8;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;

1;
