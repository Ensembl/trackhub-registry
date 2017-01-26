#!/bin/bash

ENSDIR="${ENSDIR:-$PWD}"
echo $ENSDIR

export PERL5LIB=$ENSDIR/bioperl-live:$ENSDIR/ensembl/modules:$ENSDIR/ensemblgenomes-api/modules:$PWD/src/Registry/lib

echo "Running test suite"
export TEST_POD=1

src/Registry/t/auth/script/setup.pl # initialisation for the authentication module tests
prove -v src/Registry/t/auth # test Elastisearch based catalyst authentication 
# prove -v src/Registry/t # test application

rt=$?
if [ $rt -eq 0 ]; then
  # if [ "$COVERALLS" = 'true' ]; then
  #   echo "Running Devel::Cover coveralls report"
  #   cover --nosummary -report coveralls
  # fi
  exit $?
else
  exit $rt
fi
