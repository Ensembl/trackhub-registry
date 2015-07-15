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
