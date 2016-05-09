#!/bin/bash

source ${HOME}/perl5/perlbrew/etc/bashrc
cd ${HOME}/src/trackhub-registry/src/Registry/script/production
perl dump_biosample_ids.pl
