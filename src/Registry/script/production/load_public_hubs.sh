#!/bin/bash

source ${HOME}/perl5/perlbrew/etc/bashrc
cd ${HOME}/src/trackhub-registry/src/Registry/script/production
perl load_public_hubs.pl
