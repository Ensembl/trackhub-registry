#!/bin/bash
#elasticdump
export PATH=$PATH:/nfs/public/release/ens_thr/staging/npm_nodejs/node-local/bin
 #disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=


#DATA_HOME_DIR='/nfs/public/release/ens_thr/production/elastic/elastic_datadumps'
DATA_HOME_DIR='/nfs/public/nobackup/ens_thr/production/elastic_dumps'

DATE_TIME=`date +'%d_%m_%y_%H_%M_%S'`
INPUT_HOST='http://wp-p1m-72:9200' #HH

mkdir -p ${DATA_HOME_DIR}/${DATE_TIME}
OUTPUT_DIR="${DATA_HOME_DIR}/${DATE_TIME}"
echo "Dumping indexes to ${OUTPUT_DIR}"

#Export user index
elasticdump --input=${INPUT_HOST}/users_v1 --output=${OUTPUT_DIR}/users_v1_analyzer.json  --type=analyzer
elasticdump --input=${INPUT_HOST}/users_v1 --output=${OUTPUT_DIR}/users_v1_mapping.json  --type=mapping
elasticdump --input=${INPUT_HOST}/users_v1 --output=${OUTPUT_DIR}/users_v1_data.json  --type=data

#Export trackhubs index
elasticdump --input=${INPUT_HOST}/trackhubs_v1 --output=${OUTPUT_DIR}/trackhubs_v1_analyzer.json  --type=analyzer
elasticdump --input=${INPUT_HOST}/trackhubs_v1 --output=${OUTPUT_DIR}/trackhubs_v1_mapping.json  --type=mapping
elasticdump --input=${INPUT_HOST}/trackhubs_v1 --output=${OUTPUT_DIR}/trackhubs_v1_data.json  --type=data

#Export reports index
elasticdump --input=${INPUT_HOST}/reports_v1 --output=${OUTPUT_DIR}/reports_v1_analyzer.json  --type=analyzer
elasticdump --input=${INPUT_HOST}/reports_v1 --output=${OUTPUT_DIR}/reports_v1_mapping.json  --type=mapping
elasticdump --input=${INPUT_HOST}/reports_v1 --output=${OUTPUT_DIR}/reports_v1_data.json  --type=data



