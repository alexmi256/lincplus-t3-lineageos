#!/bin/bash
# make-super.sh - assemble a new super.img for the Lincplus T3 (MT6789 / tb8781p1_64_wifi)
#
# Contents:
#   system_a       <- LineageOS 21 arm64_bgN GSI (Android 14)          REPLACED
#   vendor_a       <- OEM stock, kept (Treble: GSI runs on stock vendor)
#   vendor_dlkm_a  <- OEM stock, kept
#   odm_dlkm_a     <- OEM stock, kept
#   product_a      <- OEM stock, kept (fits with room to spare - no destructive deletion)
#   system_b       <- OEM stock, kept as-is (slot b is unused but present on this device)
#
# Geometry taken from the OEM super's own metadata (lpdump):
#   total          9,663,676,416 bytes   (9216 MiB)
#   group max      9,661,579,264 bytes   (both main_a and main_b)
#   metadata slots 3
#   header flags   virtual_ab_device
#
# NOTE on sizes: lpdump prints extents in 512-byte units on this device, NOT 4096.
# Verify any size you take from lpdump against a real extracted file before trusting it.
#
# Run inside lincplus-android-tools image with the project at /work:
#   docker run --rm -v /flashcache/hermes/projects/Lincplu.T3.Update:/work \
#     lincplus-android-tools:5 bash /work/build/make-super.sh

set -euo pipefail

G="${OEM_DIR:-/work/work/super/unpacked}"
B="${BUILD_DIR:-/work/build}"

# Optional args: <system image> [output name]
# Defaults preserve the original behaviour (LineageOS 21 / Android 14).
SYSIMG="${1:-${B}/lineage-21-arm64_bgN.img}"
OUTNAME="${2:-super-new.img}"
SYSTEM_A_SIZE=3203383296

if [ ! -f "${SYSIMG}" ]; then
  echo "ERROR: system image not found: ${SYSIMG}" >&2
  exit 1
fi
SYSIMG_BYTES=$(stat -c %s "${SYSIMG}")
if [ "${SYSIMG_BYTES}" -gt "${SYSTEM_A_SIZE}" ]; then
  echo "ERROR: ${SYSIMG} is ${SYSIMG_BYTES} bytes but system_a slot is ${SYSTEM_A_SIZE}" >&2
  exit 1
fi
echo "system_a <- ${SYSIMG} (${SYSIMG_BYTES} bytes of ${SYSTEM_A_SIZE})"

SUPER_TOTAL=9663676416
GROUP_MAX=9661579264

lpmake \
  --device "super:${SUPER_TOTAL}" \
  --metadata-slots 3 \
  --metadata-size 65536 \
  --block-size 4096 \
  --virtual-ab \
  --group "main_a:${GROUP_MAX}" \
  --group "main_b:${GROUP_MAX}" \
  --partition system_a:readonly:3203383296:main_a \
  --partition vendor_a:readonly:784695296:main_a \
  --partition vendor_dlkm_a:readonly:31756288:main_a \
  --partition odm_dlkm_a:readonly:348160:main_a \
  --partition product_a:readonly:2292097024:main_a \
  --partition system_b:readonly:120623104:main_b \
  --image "system_a=${SYSIMG}" \
  --image "vendor_a=${G}/vendor_a.img" \
  --image "vendor_dlkm_a=${G}/vendor_dlkm_a.img" \
  --image "odm_dlkm_a=${G}/odm_dlkm_a.img" \
  --image "product_a=${G}/product_a.img" \
  --image "system_b=${G}/system_b.img" \
  --output "${B}/${OUTNAME}"

echo "=== built ==="
ls -l "${B}/${OUTNAME}"
echo "=== metadata ==="
lpdump "${B}/${OUTNAME}"
