#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Storable qw/retrieve/;

@ARGV == 1 or die "Usage: deserialise.pl <file>";

my $data = retrieve $ARGV[0];
print Dumper($data);
