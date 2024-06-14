#!/bin/bash

set -a
. "__INSTALL_DIR__/env-server"
set +a

cd "__INSTALL_DIR__/app"
exec __YNH_NODE__ "__INSTALL_DIR__/app/dist/main" "$@"
