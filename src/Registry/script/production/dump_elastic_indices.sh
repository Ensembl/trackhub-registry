#!/bin/bash

# PREPARE THE ENVIRONMENT
# Activate Python Venev where node is installed from elasticdump to work
source $HOME/workspace/thr_cronjob_dir/thr_node_env/bin/activate
# Add elasticdump to PATH
export PATH=$PATH:$HOME/workspace/thr_cronjob_dir/node_modules/elasticdump/bin

# Disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

# Specify the directory where data will be dumped/backed up
DATA_HOME_DIR=$HOME'/workspace/thr_cronjob_dir/elastic_dumps'

DATE_TIME=`date +'%d_%m_%y_%H_%M_%S'`
INPUT_HOST='http://wp-p1m-72:9200' #HH

mkdir -p ${DATA_HOME_DIR}/${DATE_TIME}
OUTPUT_DIR="${DATA_HOME_DIR}/${DATE_TIME}"
echo "Dumping indexes to ${OUTPUT_DIR}"

# Export trackhubs index
elasticdump --input=${INPUT_HOST}/trackhubs_v1.2 --output=${OUTPUT_DIR}/trackhubs_v1.2_analyzer.json  --type=analyzer
elasticdump --input=${INPUT_HOST}/trackhubs_v1.2 --output=${OUTPUT_DIR}/trackhubs_v1.2_mapping.json  --type=mapping
elasticdump --input=${INPUT_HOST}/trackhubs_v1.2 --output=${OUTPUT_DIR}/trackhubs_v1.2_data.json  --type=data