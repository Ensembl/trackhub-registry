#!/bin/bash

source ~/perl5/perlbrew/etc/bashrc
bioperl_libs=( ${HOME}/src/bioperl* )
ensembl_libs=( ${HOME}/src/ensembl*/modules )
for lib_path in "${ensembl_libs[@]}" "${bioperl_libs[@]}"
do
  PERL5LIB=${PERL5LIB:+$PERL5LIB:}${lib_path}
done
export PERL5LIB

cd ${HOME}/src/trackhub-registry/src/Registry/script/production
perl ./update_trackdb_status.pl -t $1

