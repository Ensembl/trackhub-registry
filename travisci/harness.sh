#!/usr/bin/env bash

ENSDIR="${ENSDIR:-$PWD}"
echo $ENSDIR

export PERL5LIB=$ENSDIR/bioperl-live:$ENSDIR/ensembl/modules:$ENSDIR/ensemblgenomes-api/modules:$PWD/src/Registry/lib
export PYTHONPATH=/usr/local/lib/python2.7/dist-packages/:$PYTHONPATH

echo "Running test suite"
export TEST_POD=1
export CATALYST_DEBUG=0

cd src/Registry
rm -rf blib
prove -vr

exit $?
