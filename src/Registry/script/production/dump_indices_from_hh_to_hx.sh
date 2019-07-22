#elasticdump
export PATH=$PATH:/nfs/public/release/ens_thr/staging/npm_nodejs/node-local/bin

#disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

#dump trackhubs
elasticdump --input=http://wp-p1m-73:9100/trackhubs_v1 --output=http://wp-p2m-72:9200/trackhubs_v1 --type=analyzer
elasticdump --input=http://wp-p1m-73:9100/trackhubs_v1 --output=http://wp-p2m-72:9200/trackhubs_v1 --type=mapping
elasticdump --input=http://wp-p1m-73:9100/trackhubs_v1 --output=http://wp-p2m-72:9200/trackhubs_v1 --type=data

#dump reports
elasticdump --input=http://wp-p1m-73:9100/reports_v1 --output=http://wp-p2m-72:9200/reports_v1  --type=data
elasticdump --input=http://wp-p1m-73:9100/reports_v1 --output=http://wp-p2m-72:9200/reports_v1  --type=mapping
elasticdump --input=http://wp-p1m-73:9100/reports_v1 --output=http://wp-p2m-72:9200/reports_v1  --type=data
