#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

function detect_arch() {
  case "$YNH_ARCH" in
    "amd64")
      IMMICH_SERVER_VERSION="sha256:cefb3cf0755ab2db3ab44a2ff7c0d22ba71e4cafb3fa920bcdc8b815b6e23b3b"
      IMMICH_WEB_VERSION="sha256:21e67f7f959c7cf4095c885236f31566c2020e58aaa6bf0f96313569ee08b746"
      IMMICH_ML_VERSION="sha256:3b8200c85c9615c27ea87f97b90c1249fb640e65565e68e423f351d759adef0e"
      ;;

    "arm64")
      IMMICH_SERVER_VERSION="sha256:531144d66ca7ca98f457cc914b5ca674ba11a51a99d99473196745b709cb117a"
      IMMICH_WEB_VERSION="sha256:0b135a67bee3e95ac725a602c00af54bb5a20418cb61272fd489c1916fb9ce7c"
      IMMICH_ML_VERSION="sha256:85dfb39545a992845b18e99948b83b5f535e19251b570c87ca3e015e5668c793"
      ;;

    *)
      ynh_die --message="Your server architecture ($YNH_ARCH) is not supported."
      ;;
  esac
}

NODEJS_VERSION=16

# dependencies used by the app
pkg_dependencies="npm musl-dev libvips postgresql ffmpeg"

# libheif vips

#=================================================
# PERSONAL HELPERS
#=================================================

# apt-get install musl-dev
# ln -s /usr/lib/x86_64-linux-musl/libc.so /lib/libc.musl-x86_64.so.1

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================
