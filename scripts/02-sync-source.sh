#!/bin/bash
# Step 2 - initialise and sync the LineageOS tree (lineage-22.2 by default).
# Expect ~180 GB and a long first run. Resumable: run it again if it stops.
set -eu
cd "$(dirname "$0")/.."
# shellcheck source=scripts/env.sh
source scripts/env.sh

echo "workdir : $WORKDIR"
echo "branch  : $LOS_BRANCH"
echo "jobs    : $(nproc)"

"${DOCKER_RUN[@]}" -e LOS_BRANCH="$LOS_BRANCH" -e JOBS="$(nproc)" bash -c '
set -e
export HOME=/srv/home
git config --global user.name  "LOS GSI Builder"
git config --global user.email "builder@localhost"
git config --global color.ui false

ccache -M 100G 2>&1 | tail -1
cd /srv/src

if [ ! -d .repo ]; then
  repo init -u https://github.com/LineageOS/android.git -b "$LOS_BRANCH" --git-lfs
fi

repo sync -c -j"$JOBS" --no-tags --force-sync
echo "sync complete: $(du -sh /srv/src | cut -f1)"
'
