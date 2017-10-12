#elasticdump
export PATH=$PATH:/nfs/public/release/ens_thr/staging/npm_nodejs/node-local/bin

#disable proxy
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

TIMESTAMP=`date +%s%3N`
echo ${TIMESTAMP}
#dump users
elasticdump --input=http://wp-p1m-72:9200/users_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/users_v1_analyzer_${TIMESTAMP}.json  --type=analyzer
elasticdump --input=http://wp-p1m-72:9200/users_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/users_v1_mapping_${TIMESTAMP}.json   --type=mapping
elasticdump --input=http://wp-p1m-72:9200/users_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/users_v1_data_${TIMESTAMP}.json --type=data

#dump trackhubs
elasticdump --input=http://wp-p1m-72:9200/trackhubs_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/trackhubs_v1_analyzer_${TIMESTAMP}.json --type=analyzer
elasticdump --input=http://wp-p1m-72:9200/trackhubs_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/trackhubs_v1_mapping_${TIMESTAMP}.json  --type=mapping
elasticdump --input=http://wp-p1m-72:9200/trackhubs_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/trackhubs_v1_data_${TIMESTAMP}.json  --type=data

#dump reports
elasticdump --input=http://wp-p1m-72:9200/reports_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/trackhubs_v1_reports_analyzer_${TIMESTAMP}.json  --type=data
elasticdump --input=http://wp-p1m-72:9200/reports_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/trackhubs_v1_reports_mapping_${TIMESTAMP}.json  --type=mapping
elasticdump --input=http://wp-p1m-72:9200/reports_v1 --output=/nfs/public/release/ens_thr/production/elastic/elastic_datadumps/trackhubs_v1_reports_data_${TIMESTAMP}.json  --type=data


