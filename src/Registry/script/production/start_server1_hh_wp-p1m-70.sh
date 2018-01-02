#!/bin/bash -ex
# Copyright [2015-2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

HOME=/nfs/public/release/ens_thr/production/src
LOG_HOME=/nfs/public/nobackup/ens_thr/production
PORT=5001
# if ! [-z "$REGISTRY_PORT"]; then
#   PORT=$REGISTRY_PORT
# fi

# This should be the directory name/app name
APP="starman1/registry"
PIDFILE="$LOG_HOME/$APP.pid"
STATUS="$LOG_HOME/$APP.status"

# The actual path on disk to the application.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_HOME=$(cd $SCRIPT_DIR/../../ && pwd)

# Library path work
bioperl_libs=( ${HOME}/bioperl* )
ensembl_libs=( ${HOME}/ensembl*/modules )
perlbrew_libs=(/homes/ens_thrprd01/perl5/perlbrew/perls/5.16.0/lib/5.16.0)
#other_libs=(/nfs/public/release/ens_thr/production/perl5_thr/lib/perl5/x86_64-linux)
for lib_path in "${ensembl_libs[@]}" "${bioperl_libs[@]}" "${perlbrew_libs[@]}"
do
  PERL5LIB=${PERL5LIB:+$PERL5LIB:}${lib_path}
done
PERL5LIB=$APP_HOME/lib:$PERL5LIB
export PERL5LIB

#. $HOME/perl5/perlbrew/etc/bashrc
source /homes/ens_thrprd01/perl5/perlbrew/etc/bashrc

export REGISTRY_LOG4PERL=$APP_HOME'/conf/production/log4perl.conf'

# Python path for jsonschema
USER_HOME=/homes/ens_thrprd01
export PYTHONPATH=$PYTHONPATH:$USER_HOME/.local/lib/python2.7/site-packages/

# Server settings for starman
WORKERS=5
BACKLOG=1024
MAXREQUESTS=10000
RESTART_INTERVAL=1

# This is only relevant if using Catalyst
TDP_HOME="$HOME/$APP"
export TDP_HOME

ERROR_LOG="$LOG_HOME/$APP.error.log"
ACCESS_LOG="$LOG_HOME/$APP.access.log"

export REGISTRY_CONFIG=$APP_HOME/conf/production/registry.hh.conf
STARMAN="starman --backlog $BACKLOG --max-requests $MAXREQUESTS --workers $WORKERS --access-log $ACCESS_LOG --error-log $ERROR_LOG $APP_HOME/conf/production/registry.psgi"
DAEMON="/nfs/public/release/ens_thr/production/perl5_thr/bin/start_server"
#DAEMON="$HOME/perl5/perlbrew/perls/perl-5.16.0/bin/start_server"
DAEMON_OPTS="--pid-file=$PIDFILE --interval=$RESTART_INTERVAL --status-file=$STATUS --port 0.0.0.0:$PORT -- $STARMAN"

cd $APP_HOME
echo "Current working directory is " $(pwd)

# Here you could even do something like this to ensure deps are there:
# cpanm --installdeps .

res=1
if [ -f $PIDFILE ]; then
        echo "Found the file $PIDFILE; attempting a restart"
        echo "$DAEMON --restart $DAEMON_OPTS"
    ##    $DAEMON --restart $DAEMON_OPTS
        res=$?
fi

# If the restart failed (2 or 3) then try again. We could put in a kill.
if [ $res -gt 0 ]; then
    echo "Application likely not running. Starting..."
    # Rely on start-stop-daemon to run start_server in the background
    # The PID will be written by start_server
    ##/nfs/public/release/ens_thr/utils/start-stop-daemon --start --background  \
    ##    -d $APP_HOME --exec "$DAEMON" -- $DAEMON_OPTS
    /nfs/public/release/ens_thr/utils/start-stop-daemon --start --background  \
        -d $APP_HOME --exec "$DAEMON" -- $DAEMON_OPTS
fi
