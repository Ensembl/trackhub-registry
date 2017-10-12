#!/bin/bash

source  ~/.bash_profile
cd /nfs/public/release/ens_thr/production/src/trackhub-registry/src/Registry/script/production
perl update_trackdb_status.pl -t $1

