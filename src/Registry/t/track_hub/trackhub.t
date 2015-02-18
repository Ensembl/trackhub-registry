use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
  use FindBin qw/$Bin/;
  use lib "$Bin/../../lib";
}

use_ok 'Registry::TrackHub';

throws_ok { Registry::TrackHub->new() } qr/Undefined/, 'Throws if URL not passed';

my $WRONG_URL = "ftp://ftp.ebi.ac.uk/pub/databases/do_no_exist";
throws_ok { Registry::TrackHub->new(url => $WRONG_URL) } qr/check the source URL/, 'Throws with incorrect URL'; 

#
# TODO: Tests more exceptions, e.g. 
# - hub without genomesFile
# - hub without trackDb files referenced in genomesFile
#

SKIP: {
  skip "No Internet connection: cannot test TrackHub access", 8
    unless internet_connection_ok();

  my $URL = "ftp://ftp.ebi.ac.uk/pub/databases/blueprint/releases/current_release/homo_sapiens/hub";
  my $th = Registry::TrackHub->new(url => $URL);
  isa_ok($th, 'Registry::TrackHub');

  like($th->hub, qr/Blueprint_Hub/, 'Hub name');
  is($th->shortLabel, 'Blueprint Hub', 'Hub short label');
  is($th->longLabel, 'Blueprint Epigenomics Data Hub', 'Hub long label');
  is($th->genomesFile, 'genomes.txt', 'Hub genomes file');
  is($th->email, "blueprint-info\@ebi.ac.uk", 'Hub contact email');
  like($th->descriptionUrl, qr/http:\/\/www.blueprint-epigenome.eu\/index.cfm/, 'Hub description URL');

  is(scalar $th->assemblies, 1, 'Number of assemblies');
  is(($th->assemblies)[0], 'hg19', 'Stored assembly');
  is_deeply($th->genomes, { hg19 => [ "$URL/hg19/tracksDb.txt" ] }, 'Hub trackDb assembly info');
  throws_ok { $th->trackdb_conf_for_assembly } qr/Undefined/, 'Throws if assembly not defined';
  is_deeply($th->trackdb_conf_for_assembly('hg19'), [ "$URL/hg19/tracksDb.txt" ], 'TrackDB conf for assembly');
}

sub internet_connection_ok {
  #
  # For some reason, Net::Ping doeesn't reach the host
  # even if the connection is ok and ping works
  # on the command line
  #
  # my $p = Net::Ping->new();
  # my $ok = $p->ping("www.google.com", 5);
  # $p->close();
  # return $ok;
  
  use HTTP::Tiny;
  return HTTP::Tiny->new()->request('GET', "http://www.google.com")->{success};
}

done_testing();
