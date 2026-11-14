#!/bin/bash
# Step 3 - clone Andy Yan's GSI tooling and build the system image.
#
#   scripts/03-build.sh            # full: sync local manifests, apply patches, build
#   scripts/03-build.sh nosync     # skip sync + patching (tree already prepared)
#
# Expect ~2 hours cold, much less with a warm ccache.
set -eu
cd "$(dirname "$0")/.."
# shellcheck source=scripts/env.sh
source scripts/env.sh

EXTRA="${1:-}"
export TARGET

"${DOCKER_RUN[@]}" -e TARGET="$TARGET" -e EXTRA="$EXTRA" bash -c '
set -e
export HOME=/srv/home
cd /srv/src

# GSI tooling (lineage-22-light branch = Android 15 Light builds)
for spec in "lineage_build_unified lineage-22-light" \
            "lineage_patches_unified lineage-22-light" \
            "android_device_lineage_gsi lineage-22"; do
  set -- $spec
  [ -d "$1" ] || git clone -q -b "$2" "https://github.com/AndyCGYan/$1"
done

bash lineage_build_unified/build_unified.sh treble "$TARGET" $EXTRA
'
