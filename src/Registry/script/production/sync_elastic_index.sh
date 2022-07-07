#!/usr/bin/sh

# Elasticdump location
export PATH=$PATH:/homes/<tark_dev_username>/workspace/node_modules/elasticdump/bin

# Disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

INPUT_HOST='http://wp-p1m-72:9200'  #HH
OUTPUT_HOST='http://wp-p2m-72:9200' #HX

# DELETE FROM OUTPUT HOST
# HX HOST IS READONLY- So before delete change it to false
# Added -H to fix: https://stackoverflow.com/a/47545023/4488332
curl -XPUT ${OUTPUT_HOST}/trackhubs_v1.2/_settings -d '{"index":{"blocks.read_only":false}}' -H 'Content-Type: application/json'
  
# Delete the index
curl -XDELETE ${OUTPUT_HOST}/trackhubs_v1.2

# LOAD the index from HH to HX
# Dump trackhubs
elasticdump --input=${INPUT_HOST}/trackhubs_v1.2 --output=${OUTPUT_HOST}/trackhubs_v1.2 --type=analyzer
elasticdump --input=${INPUT_HOST}/trackhubs_v1.2 --output=${OUTPUT_HOST}/trackhubs_v1.2 --type=mapping
elasticdump --input=${INPUT_HOST}/trackhubs_v1.2 --output=${OUTPUT_HOST}/trackhubs_v1.2 --type=data

# Create alias
curl -XPOST "${OUTPUT_HOST}/_aliases/" -d '{ "actions": [{ "add": { "index": "trackhubs_v1.2", "alias": "trackhubs" }} ] }' -H 'Content-Type: application/json'


# HX HOST IS READONLY- So before delete change it to false
curl -XPUT ${OUTPUT_HOST}/trackhubs_v1.2/_settings -d '{"index":{"blocks.read_only":true}}' -H 'Content-Type: application/json'











