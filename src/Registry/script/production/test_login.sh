#!/bin/bash

cd ${HOME}/src/trackhub-registry/src/Registry/script/production
user=$1
pass=$2

perl test_login.pl $user $pass || {
    printf 'Logging does not work\nRestarting server...' >> logs/test_loging.log
    # stop_server.sh
    # start_server.sh
    # exit 1
}