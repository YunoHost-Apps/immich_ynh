#!/bin/bash

set -a
source "__INSTALL_DIR__/env"
set +a

cd "__INSTALL_DIR__/app/machine-learning"
source venv/bin/activate

: "${MACHINE_LEARNING_HOST:=127.0.0.1}"
: "${MACHINE_LEARNING_PORT:=__PORT_MACHINELEARNING__}"
: "${MACHINE_LEARNING_WORKERS:=1}"
: "${MACHINE_LEARNING_WORKER_TIMEOUT:=120}"

exec gunicorn app.main:app \
        -k app.config.CustomUvicornWorker \
        -w "$MACHINE_LEARNING_WORKERS" \
        -b "$MACHINE_LEARNING_HOST":"$MACHINE_LEARNING_PORT" \
        -t "$MACHINE_LEARNING_WORKER_TIMEOUT" \
        --log-config-json log_conf.json \
        --graceful-timeout 0
