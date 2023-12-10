#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

function detect_arch() {
  case "$YNH_ARCH" in
    "amd64")
      IMMICH_SERVER_VERSION="sha256:f65d1a5c6cf5b21ee788a23f88f082e6aef2bec3989c397185117e313af9f4ec"
      IMMICH_WEB_VERSION="sha256:ba81480c999185355fed0ee4470a51028ec7bd691d3466edbf68fecbaab784a4"
      IMMICH_ML_VERSION="sha256:f98ebcc420a6de46ffc4fe624cd6c47082248695834b6ef0e3df32c519154a08"
      ;;

    "arm64")
      IMMICH_SERVER_VERSION="sha256:e26d40b487940202185b37a3762c47f3bbbdeb31987daf8aef79054cff087313"
      IMMICH_WEB_VERSION="sha256:b6e49e1a3fed0a14cfc5ce5566dd04b6640e55db4caaade72126cd2734e1f3b1"
      IMMICH_ML_VERSION="sha256:a7298ebdab1d37e01441bbf2196ba2b2c56b0bef483be252f1e6d02dbd0b430c"
      ;;

    *)
      ynh_die --message="Your server architecture ($YNH_ARCH) is not supported."
      ;;
  esac
}

NODEJS_VERSION=18

#=================================================
# PERSONAL HELPERS
#=================================================

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================
