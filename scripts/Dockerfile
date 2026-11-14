# Builder image for LineageOS 22.2 GSI builds.
#
# Modern AOSP ships clang, JDK, ninja and make inside prebuilts/, so the host image only needs
# the small package list from source.android.com plus the three LineageOS extras:
#   git-lfs     - `repo init --git-lfs`
#   ccache      - not shipped by AOSP
#   erofs-utils - erofs system images
#
# Do NOT add openjdk/clang/ninja here: they arrive with the synced tree.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 \
      x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils \
      xsltproc unzip fontconfig python3 ca-certificates openssl \
      git-lfs ccache erofs-utils lz4 rsync bc file procps \
      e2fsprogs android-sdk-libsparse-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod a+x /usr/local/bin/repo

ENV USE_CCACHE=1 \
    CCACHE_DIR=/srv/ccache \
    CCACHE_EXEC=/usr/bin/ccache

WORKDIR /srv/src
