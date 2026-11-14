#!/bin/bash
# Step 0 - extract the OEM partitions that must be KEPT from your own stock super.img.
#
#   scripts/00-extract-oem.sh /path/to/FW/.../images/super.img
#
# Output: $WORKDIR/oem/{vendor_a,vendor_dlkm_a,odm_dlkm_a,product_a,system_b}.img
#
# These are proprietary OEM blobs and are NOT distributed with this repository - you must pull
# them from your own device's firmware package. Anything that ships them is redistributing
# vendor code it has no right to.
#
# Needs: simg2img (android-sdk-libsparse-utils) and lpunpack (from AOSP otatools, or a distro
# package). lpunpack appears in $SRC/out/host/linux-x86/bin after `make otatools`.
set -eu
cd "$(dirname "$0")/.."
# shellcheck source=scripts/env.sh
source scripts/env.sh

STOCK="${1:?usage: $0 /path/to/stock/super.img}"
OUT="$WORKDIR/oem"
RAW="$WORKDIR/super.raw"
mkdir -p "$OUT"

LPUNPACK="${LPUNPACK:-$(command -v lpunpack || true)}"
[ -n "$LPUNPACK" ] || LPUNPACK="$SRC/out/host/linux-x86/bin/lpunpack"
if [ ! -x "$LPUNPACK" ]; then
  echo "ERROR: lpunpack not found." >&2
  echo "  Build it with:  cd $SRC && source build/envsetup.sh && lunch ... && make otatools" >&2
  echo "  or export LPUNPACK=/path/to/lpunpack" >&2
  exit 1
fi

echo "== converting sparse -> raw if needed"
if file "$STOCK" | grep -qi "android sparse"; then
  simg2img "$STOCK" "$RAW"
else
  cp -f "$STOCK" "$RAW"
fi

echo "== unpacking logical partitions"
"$LPUNPACK" "$RAW" "$OUT"

echo "== result"
for p in vendor_a vendor_dlkm_a odm_dlkm_a product_a system_b; do
  if [ -f "$OUT/$p.img" ]; then
    printf "  %-14s %s\n" "$p" "$(stat -c %s "$OUT/$p.img") bytes"
  else
    printf "  %-14s MISSING - check the partition names in your super\n" "$p"
  fi
done
echo
echo "Keep these: they are the only piece of the OEM firmware the build needs."
