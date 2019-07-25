#elasticdump
export PATH=$PATH:/homes/ens_thrprd01/node/node-v10.16.0-linux-x64/bin:/homes/ens_thrprd01/node/node-v10.16.0-linux-x64/node_modules/elasticdump/bin

#disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

#dump trackhubs
elasticdump --input=http://wp-p1m-73:9200/trackhubs --output=http://wp-p2m-72:9200/trackhubs --type=analyzer
elasticdump --input=http://wp-p1m-73:9200/trackhubs --output=http://wp-p2m-72:9200/trackhubs --type=mapping
elasticdump --input=http://wp-p1m-73:9200/trackhubs --output=http://wp-p2m-72:9200/trackhubs --type=data

#dump reports
elasticdump --input=http://wp-p1m-73:9200/reports --output=http://wp-p2m-72:9200/reports --type=data
elasticdump --input=http://wp-p1m-73:9200/reports --output=http://wp-p2m-72:9200/reports --type=mapping
elasticdump --input=http://wp-p1m-73:9200/reports --output=http://wp-p2m-72:9200/reports --type=data
