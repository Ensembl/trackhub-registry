#
# Must install LWP::Protocol::https
#
# See http://search.cpan.org/~mschilli/LWP-Protocol-https-6.06/lib/LWP/Protocol/https.pm
#
# If hostname verification is requested by LWP::UserAgent's ssl_opts, and neither SSL_ca_file nor SSL_ca_path is set, 
# then SSL_ca_file is implied to be the one provided by Mozilla::CA. 
# If the Mozilla::CA module isn't available SSL requests will fail. Either install this module, set up an alternative 
# SSL_ca_file or disable hostname verification.
#
# Note: hostname verification can be skipped by Ensembl plants pipeline, they should trust us
#
use strict;
use warnings;

use LWP::UserAgent;	
use Data::Dumper;

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
my $res = $ua->get("https://twitter.com");
