#!/usr/bin/env bash

URL=https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION.tar.gz

if [ ! -d "$ES_HOME" ]; then
  wget $URL
  tar xzf elasticsearch-$ELASTICSEARCH_VERSION.tar.gz
  mkdir -p $ES_HOME/data
  mv elasticsearch-$ELASTICSEARCH_VERSION/* $ES_HOME/
fi
# Debugging
# cat $ES_HOME/config/jvm.options

ls -l $JAVA_HOME/lib/

sudo echo 'permission javax.management.MBeanTrustPermission "register"' >> $JAVA_HOME/jre/lib/security/java.policy

# $ES_HOME/bin/elasticsearch -d