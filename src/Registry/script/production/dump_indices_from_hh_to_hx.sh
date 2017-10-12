#elasticdump
export PATH=$PATH:/nfs/public/release/ens_thr/staging/npm_nodejs/node-local/bin

#disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

#dump users
elasticdump --input=http://wp-p1m-72:9200/users_v1 --output=http://wp-p2m-72:9200/users_v1 --type=analyzer
elasticdump --input=http://wp-p1m-72:9200/users_v1 --output=http://wp-p2m-72:9200/users_v1 --type=mapping
elasticdump --input=http://wp-p1m-72:9200/users_v1 --output=http://wp-p2m-72:9200/users_v1 --type=data

#dump trackhubs
elasticdump --input=http://wp-p1m-72:9200/trackhubs_v1 --output=http://wp-p2m-72:9200/trackhubs_v1 --type=analyzer
elasticdump --input=http://wp-p1m-72:9200/trackhubs_v1 --output=http://wp-p2m-72:9200/trackhubs_v1 --type=mapping
elasticdump --input=http://wp-p1m-72:9200/trackhubs_v1 --output=http://wp-p2m-72:9200/trackhubs_v1 --type=data

#dump reports
elasticdump --input=http://wp-p1m-72:9200/reports_v1 --output=http://wp-p2m-72:9200/reports_v1  --type=data
elasticdump --input=http://wp-p1m-72:9200/reports_v1 --output=http://wp-p2m-72:9200/reports_v1  --type=mapping
elasticdump --input=http://wp-p1m-72:9200/reports_v1 --output=http://wp-p2m-72:9200/reports_v1  --type=data


#Add aliases - Only first time - So comment out
#curl -XPOST "http://wp-p2m-72:9200/_aliases/" -d '{ "actions": [  { "add": { "index": "trackhubs_v1", "alias": "trackhubs" }} ] }'
#curl -XPOST "http://wp-p2m-72:9200/_aliases/" -d '{ "actions": [  { "add": { "index": "users_v1", "alias": "users" }} ] }'
#curl -XPOST "http://wp-p2m-72:9200/_aliases/" -d '{ "actions": [  { "add": { "index": "reports_v1", "alias": "reports" }} ] }'



