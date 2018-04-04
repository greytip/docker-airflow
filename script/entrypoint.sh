#!/usr/bin/env bash

AIRFLOW_HOME="/usr/local/airflow"
CMD="airflow"
TRY_LOOP="20"
SQL_ALCHEMY_CONN="postgresql+psycopg2://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB" 
RESULT_BACKEND="db+postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB" 
BROKER_URL="redis://$REDIS_PREFIX$REDIS_HOST:$REDIS_PORT/$REDIS_DB"

#echo $SQL_ALCHEMY_CONN
#echo $RESULT_BACKEND
#echo $BROKER_URL


cp "$AIRFLOW_HOME"/etc/airflow.cfg "$AIRFLOW_HOME"/airflow.cfg
mkdir "$AIRFLOW_HOME"/dags
mkdir "$AIRFLOW_HOME"/plugins
cp -L  /tmp/dags/*.py "$AIRFLOW_HOME"/dags
cp -L  /tmp/plugins/*.py "$AIRFLOW_HOME"/plugins

function replace_vars() {
   local vars
   local name
   name=$1[@]
   vars=("${!name}")
   for v in ${vars[@]}; do
     value=${!v}
     #echo "$v=$value"
     #echo "sed -i -e 's/__${v}__/$value/' $2"
     sed -i -e "s|__${v}__|$value|" $2
   done
}

VARS=( SQL_ALCHEMY_CONN RESULT_BACKEND BROKER_URL )

replace_vars VARS "$AIRFLOW_HOME"/airflow.cfg

# Install custome python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    $(which pip) install --user -r /requirements.txt
fi

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_PREFIX=:${REDIS_PASSWORD}@
else
    REDIS_PREFIX=
fi

# Wait for Postresql
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] ; then
  i=0
  while ! nc -z $POSTGRES_HOST $POSTGRES_PORT >/dev/null 2>&1 < /dev/null; do
    i=$((i+1))
    if [ "$1" = "webserver" ]; then
      echo "$(date) - waiting for ${POSTGRES_HOST}:${POSTGRES_PORT}... $i/$TRY_LOOP"
      if [ $i -ge $TRY_LOOP ]; then
        echo "$(date) - ${POSTGRES_HOST}:${POSTGRES_PORT} still not reachable, giving up"
        exit 1
      fi
    fi
    sleep 10
  done
fi

# Wait for Redis
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] || [ "$1" = "flower" ] ; then
  j=0
  while ! nc -z $REDIS_HOST $REDIS_PORT >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo "$(date) - $REDIS_HOST still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for Redis... $j/$TRY_LOOP"
    sleep 5
  done
fi

if [ "$1" = "webserver" ]; then
  echo "Initialize database..."
  $CMD initdb
  exec $CMD webserver
else
  sleep 10
  exec $CMD "$@"
fi
