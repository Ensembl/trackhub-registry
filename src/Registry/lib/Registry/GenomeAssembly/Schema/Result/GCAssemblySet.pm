=head1 LICENSE

Copyright [2015-2018] EMBL-European Bioinformatics Institute

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

package Registry::GenomeAssembly::Schema::Result::GCAssemblySet;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('gc_assembly_set');
__PACKAGE__->add_columns(qw/ set_acc set_chain set_version name long_name is_patch tax_id common_name scientific_name file_md5 filesafename audit_time audit_user audit_osuser status_id genome_representation assembly_level first_created last_updated center_name /);
__PACKAGE__->set_primary_key('set_acc');
# __PACKAGE__->has_many(cds => 'MyApp::Schema::Result::CD', 'artistid');

1;
