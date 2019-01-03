#!/bin/bash
# Copyright [2015-2019] EMBL-European Bioinformatics Institute
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
APP="starman2/registry"
PIDFILE="$LOG_HOME/$APP.pid"
STATUS="$LOG_HOME/$APP.status"

/nfs/public/release/ens_thr/utils/start-stop-daemon --stop --oknodo --pidfile ${PIDFILE}
