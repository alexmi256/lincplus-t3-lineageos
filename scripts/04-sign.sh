#!/bin/bash
# Step 4 - sign the build with your own release keys.
#
# Produces ~/los22/home/build-output/lineage-22.2-<date>-UNOFFICIAL-gsi_arm64_gN-signed.img
#
# Requires steps 2 and 3 to have run. target-files-package + otatools are built here if missing.
# Time: ~20-40 min for a warm tree, longer if `out/` was cleaned.
#
# WARNING: without `set -u` on purpose - build/envsetup.sh breaks under it (lunch: command not found).
set -e
cd "$(dirname "$0")/.."
# shellcheck source=scripts/env.sh
source scripts/env.sh

REPO_DIR="$(pwd)"

"${DOCKER_RUN[@]}" \
  -v "$REPO_DIR":/repo:ro \
  -e TARGET="$TARGET" \
  bash -c '
export HOME=/srv/home
cd /srv/src

echo "== 1/4 generating keys"
bash /repo/scripts/make-certs.sh

echo "== 2/4 converting keys to PEM (avbtool needs PEM for APEX payloads)"
CERTS=/srv/home/.android-certs bash /repo/scripts/convert-pem.sh

echo "== 3/4 preparing build environment"
source build/envsetup.sh > /tmp/envsetup.log 2>&1
source vendor/lineage/vars/aosp_target_release
lunch "lineage_gsi_arm64_gN-${aosp_target_release}-userdebug" > /tmp/lunch.log 2>&1 || {
  tail -5 /tmp/lunch.log; exit 1; }
echo "OUT=$OUT  release=${aosp_target_release}"

echo "== 4/4 signing target files"
if ! ls "$OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip >/dev/null 2>&1; then
  echo "   target_files missing - building them (this takes a while)"
  make -j"$(nproc --all)" target-files-package otatools
fi

bash lineage_build_unified/sign_target_files.sh "$OUT/signed-target_files.zip"
unzip -joq "$OUT/signed-target_files.zip" IMAGES/system.img -d "$OUT"

OUTNAME="/srv/home/build-output/lineage-22.2-$(date -u +%Y%m%d)-UNOFFICIAL-gsi_arm64_gN-signed.img"
mkdir -p /srv/home/build-output
cp -f "$OUT/system.img" "$OUTNAME"
echo "signed system image: $OUTNAME"
ls -l "$OUTNAME"
sha256sum "$OUTNAME"
'
