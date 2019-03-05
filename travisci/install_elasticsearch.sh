#!/bin/bash

CACHE_DIR=$HOME/elasticsearch/

URL=https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION.tar.gz

wget $URL
tar xzf elasticsearch-$ELASTICSEARCH_VERSION.tar.gz
mv elasticsearch-$ELASTICSEARCH_VERSION/* $ES_HOME/