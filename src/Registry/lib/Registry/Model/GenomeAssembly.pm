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

package Registry::Model::GenomeAssembly;

#
# Interface to the content of the assembly set table
# of the GenomeAssembly DB as a document stored in
# the ES instance.
# The content is loaded from file, which is a dump of
# the original table.
#

use Moose;
use namespace::autoclean;
extends 'Catalyst::Model';



__PACKAGE__->meta->make_immutable;
1;
