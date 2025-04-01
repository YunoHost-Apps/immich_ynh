#!/bin/bash

set -a
source "__INSTALL_DIR__/env"
set +a

cd "__INSTALL_DIR__/app/machine-learning"
source venv/bin/activate

: "${IMMICH_HOST:=127.0.0.1}"
: "${MACHINE_LEARNING_PORT:=__PORT_MACHINELEARNING__}"
: "${MACHINE_LEARNING_WORKERS:=1}"
: "${MACHINE_LEARNING_HTTP_KEEPALIVE_TIMEOUT_S:=2}"
: "${MACHINE_LEARNING_WORKER_TIMEOUT:=300}"
: "${MACHINE_LEARNING_CACHE_FOLDER:=__INSTALL_DIR__/cache}"
: "${TRANSFORMERS_CACHE:=__INSTALL_DIR__/cache}"

exec gunicorn immich_ml.main:app \
	-k immich_ml.config.CustomUvicornWorker \
	-c immich_ml/gunicorn_conf.py \
	-b "$IMMICH_HOST":"$IMMICH_PORT" \
	-w "$MACHINE_LEARNING_WORKERS" \
	-t "$MACHINE_LEARNING_WORKER_TIMEOUT" \
	--log-config-json log_conf.json \
	--keep-alive "$MACHINE_LEARNING_HTTP_KEEPALIVE_TIMEOUT_S" \
	--graceful-timeout 10
