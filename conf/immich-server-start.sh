#!/bin/bash

set -a
source "__INSTALL_DIR__/env-server"
set +a

cd "__INSTALL_DIR__/app"
exec __NODEJS_DIR__/node "__INSTALL_DIR__/app/dist/main" "$@"
