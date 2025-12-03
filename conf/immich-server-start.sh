#!/bin/bash

set -a
source "__INSTALL_DIR__/immich/env"
set +a

cd "__INSTALL_DIR__/immich/app"
exec __NODEJS_DIR__/node "__INSTALL_DIR__/immich/app/dist/main" "$@"
