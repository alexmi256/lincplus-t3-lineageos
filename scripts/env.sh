#!/bin/bash
# Shared environment for the build pipeline. Source this, do not execute it.
#
#   source scripts/env.sh
#
# Every path and knob can be overridden by exporting it beforehand.

export WORKDIR="${WORKDIR:-$HOME/los22}"      # scratch root for tree, ccache and output
export SRC="$WORKDIR/src"                      # LineageOS tree (bind -> /srv/src)
export CCACHE_DIR_HOST="$WORKDIR/ccache"       # bind -> /srv/ccache
export HOMEMNT="$WORKDIR/home"                 # container HOME (bind -> /srv/home)
export LOGDIR="$WORKDIR/logs"

export BUILDER_IMAGE="${BUILDER_IMAGE:-los22-builder}"
export TARGET="${TARGET:-64GN}"                # 64GN = GApps, 64VN = vanilla
export LOS_BRANCH="${LOS_BRANCH:-lineage-22.2}"

# NOTE on rootless Docker: do NOT add `-u $(id -u):$(id -g)`.
# Under a rootless daemon container root maps to the host user, while container uid 1000 maps to a
# subuid and cannot write the bind mounts. See docs/13-docker-build-env-research.md.
DOCKER_RUN=(docker run --rm
  -v "$SRC":/srv/src
  -v "$CCACHE_DIR_HOST":/srv/ccache
  -v "$HOMEMNT":/srv/home
  -v "$LOGDIR":/srv/logs
  "$BUILDER_IMAGE")

mkdir -p "$SRC" "$CCACHE_DIR_HOST" "$HOMEMNT" "$LOGDIR"
