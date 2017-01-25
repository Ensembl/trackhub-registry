#!/bin/bash

ENSDIR="${ENSDIR:-$PWD}"
echo $ENSDIR

export PERL5LIB=$ENSDIR/bioperl-live:$ENSDIR/ensembl/modules:$ENSDIR/ensemblgenomes-api/modules:$PWD/src/Registry/lib

echo "Running test suite"
export TEST_POD=1

# if [ "$COVERALLS" = 'true' ]; then
#   PERL5OPT='-MDevel::Cover=+ignore,bioperl,+ignore,ensembl-test,+ignore,ensembl-variation,ensembl-compara' perl $ENSDIR/ensembl-test/scripts/runtests.pl -verbose modules/t $SKIP_TESTS
# else
#   perl $ENSDIR/ensembl-test/scripts/runtests.pl modules/t $SKIP_TESTS
# fi
perl src/Registry/t/03podcoverage.t

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
