FROM debian:${DEBIAN_VERSION}-slim

ARG VIPS_VERSION
ARG HEIF_VERSION
ARG PREFIX=/opt/vips

RUN apt-get update && apt-get install -y \
    build-essential cmake meson ninja-build pkg-config \
    wget xz-utils tar \
    libglib2.0-dev libexpat1-dev zlib1g-dev \
    libjpeg-dev libpng-dev libtiff-dev libgif-dev \
    libwebp-dev libaom-dev libde265-dev libdav1d-dev \
    libimagequant-dev libraw-dev libexif-dev libcgif-dev

# libheif
RUN cd /tmp \
 && wget -q https://github.com/strukturag/libheif/releases/download/v${HEIF_VERSION}/libheif-${HEIF_VERSION}.tar.gz \
 && tar xf libheif-${HEIF_VERSION}.tar.gz \
 && cd libheif-${HEIF_VERSION} \
 && mkdir build && cd build \
 && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${PREFIX} \
 && make -j$(nproc) && make install

# libvips
RUN cd /tmp \
 && wget -q https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz \
 && tar xf vips-${VIPS_VERSION}.tar.xz \
 && cd vips-${VIPS_VERSION} \
 && meson setup build --buildtype=release --prefix=${PREFIX} \
 && ninja -C build install

CMD ["bash"]
