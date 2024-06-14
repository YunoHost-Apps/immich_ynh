#!/bin/bash

set -a
source "__INSTALL_DIR__/env-machine-learning"
set +a

cd "__INSTALL_DIR__/app/machine-learning"
source venv/bin/activate

: "${IMMICH_HOST:=127.0.0.1}"
: "${IMMICH_PORT:=__PORT_MACHINELEARNING__}"
: "${MACHINE_LEARNING_WORKERS:=1}"
: "${MACHINE_LEARNING_WORKER_TIMEOUT:=120}"

exec gunicorn app.main:app \
        -k app.config.CustomUvicornWorker \
        -b "$IMMICH_HOST":"$IMMICH_PORT" \
        -w "$MACHINE_LEARNING_WORKERS" \
        -t "$MACHINE_LEARNING_WORKER_TIMEOUT" \
        --log-config-json log_conf.json \
        --graceful-timeout 0
