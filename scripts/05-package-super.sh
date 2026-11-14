#!/bin/bash
# Step 5 - apply the Widevine identity fix and assemble the flashable super.img.
#
#   scripts/05-package-super.sh [system.img] [output-name]
#
# Without the identity patch the device boots fine but Widevine drops to L3.
# See docs/10-widevine-l1-on-gsi.md for why.
set -eu
cd "$(dirname "$0")/.."
# shellcheck source=scripts/env.sh
source scripts/env.sh

REPO_DIR="$(pwd)"
SYSIMG="${1:-$(ls -t "$HOMEMNT"/build-output/*.img 2>/dev/null | head -1)}"
[ -n "${SYSIMG:-}" ] || { echo "ERROR: no system image found in $HOMEMNT/build-output" >&2; exit 1; }
OUTNAME="${2:-super-lin22-signed.img}"

[ -d "$WORKDIR/oem" ] || { echo "ERROR: run scripts/00-extract-oem.sh first" >&2; exit 1; }

echo "system image : $SYSIMG"
echo "output       : $OUTNAME"

docker run --rm \
  -v "$SRC":/srv/src \
  -v "$REPO_DIR":/repo:ro \
  -v "$WORKDIR/oem":/oem \
  -v "$(dirname "$SYSIMG")":/build \
  -e SYSIMG="/build/$(basename "$SYSIMG")" \
  -e OUTNAME="$OUTNAME" \
  -e OEM_DIR=/oem \
  -e BUILD_DIR=/build \
  "$BUILDER_IMAGE" bash -c '
set -e
if ! command -v lpmake >/dev/null 2>&1; then
  if [ -x /srv/src/out/host/linux-x86/bin/lpmake ]; then
    export PATH=/srv/src/out/host/linux-x86/bin:$PATH
  else
    echo "ERROR: lpmake not found (build otatools: make otatools / use an android-tools image)" >&2
    exit 1
  fi
fi

# 1. identity patch: all three prop overlays, or the product overlay wins and Widevine stays L3
bash /repo/scripts/patch-gsi-identity.sh "$SYSIMG"

# 2. wrap it in a super alongside the untouched OEM partitions
bash /repo/scripts/make-super.sh "$SYSIMG" "$OUTNAME"
'
