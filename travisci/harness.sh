#!/bin/bash

ENSDIR="${ENSDIR:-$PWD}"
echo $ENSDIR

export PERL5LIB=$ENSDIR/bioperl-live:$ENSDIR/ensembl/modules:$ENSDIR/ensemblgenomes-api/modules:$PWD/src/Registry/lib
export PYTHONPATH=/usr/local/lib/python2.7/dist-packages/:$PYTHONPATH

echo "import jsonschema" > test.py
echo "print 'Import succeeded'" >> test.py
echo "Running python test"
python test.py
echo "done"

echo "Running test suite"
export TEST_POD=1
export CATALYST_DEBUG=0

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
