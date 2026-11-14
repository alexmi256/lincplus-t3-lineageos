#!/bin/bash
# Step 6 - flash a super image and wipe data.
#
#   scripts/06-flash.sh super-lin22-signed.img [vbmeta-flags3.img]
#
# DESTRUCTIVE: userdata is erased. That is deliberate and required - flashing a new super without
# wiping has caused bootloops. `fastboot -w` from fastbootd silently skips userdata, so this script
# uses `fastboot erase userdata` explicitly.
set -eu
SUPER="${1:?usage: $0 <super.img> [vbmeta-flags3.img]}"
VBMETA="${2:-vbmeta-flags3.img}"

[ -f "$SUPER" ] || { echo "ERROR: $SUPER not found" >&2; exit 1; }

echo "About to:"
echo "  flash super   <- $SUPER"
echo "  flash vbmeta  <- $VBMETA   (Flags: 3, required)"
echo "  erase userdata + metadata  (ALL DATA WILL BE LOST)"
echo
printf "Type YES to continue: "
read -r ok
[ "$ok" = "YES" ] || { echo "aborted"; exit 1; }

echo "== checking device"
fastboot devices
count=$(fastboot devices | grep -c . || true)
[ "$count" = "1" ] || { echo "ERROR: expected exactly one fastboot device, got $count" >&2; exit 1; }

echo "== entering fastbootd"
adb reboot fastboot 2>/dev/null || true
sleep 20
fastboot devices

echo "== flashing super (~3-4 minutes)"
fastboot flash super "$SUPER"

echo "== flashing vbmeta"
# In fastbootd this can fail with 'No such file or directory'; reboot to the bootloader and retry
# there if that happens. It only needs writing when yours is not already Flags: 3.
fastboot flash vbmeta "$VBMETA" || echo "!! vbmeta failed here - retry from 'adb reboot bootloader'"

echo "== wiping"
fastboot erase userdata
fastboot erase metadata

echo "== rebooting"
fastboot reboot
echo
echo "First boot takes 1-3 minutes. Verify with:"
echo "  adb shell getprop ro.build.version.release    # 15 or 14"
echo "  adb shell getprop ro.product.brand            # Lincplus if the identity patch applied"
