#!/bin/bash

ENSDIR="${ENSDIR:-$PWD}"
echo $ENSDIR

export PERL5LIB=$ENSDIR/bioperl-live:$ENSDIR/ensembl/modules:$ENSDIR/ensemblgenomes-api/modules:$PWD/src/Registry/lib
export PYTHONPATH=/usr/local/lib/python2.7/dist-packages/:$PYTHONPATH

echo "import jsonschema" > test.py
python test.py

echo "Running test suite"
export TEST_POD=1
export CATALYST_DEBUG=0

cd src/Registry
rm -rf blib
t/auth/script/setup.pl # initialisation for testing the authentication module
prove -vr

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
