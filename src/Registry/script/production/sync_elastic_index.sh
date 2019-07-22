#!/usr/bin/sh

#Load json files to index

#SETTINGS

#elasticdump
export PATH=$PATH:/nfs/public/release/ens_thr/staging/npm_nodejs/node-local/bin
 #disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

INPUT_HOST='http://wp-p1m-73:9100'  #HH
OUTPUT_HOST='http://wp-p2m-72:9200' #HX

#DELETE FROM OUTPUT HOST
# HX HOST IS READONLY- So before delete change it to false
curl -XPUT ${OUTPUT_HOST}/reports/_settings -d '{"index":{"blocks.read_only":false}}'
curl -XPUT ${OUTPUT_HOST}/trackhubs/_settings -d '{"index":{"blocks.read_only":false}}'
  
# Delete the index
curl -XDELETE ${OUTPUT_HOST}/users_v1
curl -XDELETE ${OUTPUT_HOST}/trackhubs_v1
curl -XDELETE ${OUTPUT_HOST}/reports_v1

# LOAD the index from HH to HX
 
#dump trackhubs
elasticdump --input=${INPUT_HOST}/trackhubs_v1 --output=${OUTPUT_HOST}/trackhubs_v1 --type=analyzer
elasticdump --input=${INPUT_HOST}/trackhubs_v1 --output=${OUTPUT_HOST}/trackhubs_v1 --type=mapping
elasticdump --input=${INPUT_HOST}/trackhubs_v1 --output=${OUTPUT_HOST}/trackhubs_v1 --type=data
 
#dump reports
elasticdump --input=${INPUT_HOST}/reports_v1 --output=${OUTPUT_HOST}/reports_v1  --type=data
elasticdump --input=${INPUT_HOST}/reports_v1 --output=${OUTPUT_HOST}/reports_v1  --type=mapping
elasticdump --input=${INPUT_HOST}/reports_v1 --output=${OUTPUT_HOST}/reports_v1  --type=data

#create alias
curl -XPOST "${OUTPUT_HOST}/_aliases/" -d '{ "actions": [{ "add": { "index": "trackhubs_v1", "alias": "trackhubs" }} ] }'
curl -XPOST "${OUTPUT_HOST}/_aliases/" -d '{ "actions": [{ "add": { "index": "reports_v1", "alias": "reports" }} ] }'



# HX HOST IS READONLY- So before delete change it to false
curl -XPUT ${OUTPUT_HOST}/reports_v1/_settings -d '{"index":{"blocks.read_only":true}}'
curl -XPUT ${OUTPUT_HOST}/users_v1/_settings -d '{"index":{"blocks.read_only":true}}'
curl -XPUT ${OUTPUT_HOST}/trackhubs_v1/_settings -d '{"index":{"blocks.read_only":true}}'











