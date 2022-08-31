#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

function detect_arch() {
  case "$YNH_ARCH" in
    "amd64")
      IMMICH_SERVER_VERSION="sha256:0d2f7df9b2d4f9f17c9e62f63229e899e218deb86eb306514834d59b65305bc7"
      IMMICH_WEB_VERSION="sha256:d887d1e32fa00bbe617df55c1e3ba1ee456dfa5d28569a5bab2d92b406748a7f"
      IMMICH_ML_VERSION="sha256:201d5787bddfa4341a42826d06b33ede0729816f7bab597b747a1cd38bf39f83"
      ;;

    "arm64")
      IMMICH_SERVER_VERSION="sha256:3b4179138da8d8e79ccab2d079901afe8b9a2d28036a2546c6ecd6ece1b2a3a1"
      IMMICH_WEB_VERSION="sha256:23d614fa02853c4506731ed7080be1f0f83466f1ff961b68a933e51184d2e5fc"
      IMMICH_ML_VERSION="sha256:5fa3128675210e0b8df1320678b76ad7c375fbc5a61108f39c46056e5a3ee7c8"
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
