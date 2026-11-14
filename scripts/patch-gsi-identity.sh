#!/bin/bash
# patch-gsi-identity.sh - give a GSI the stock build identity so the vendor Widevine CDM
# provisions L1 instead of falling back to provisional L3.
#
# WHY: on this device Widevine lives only in /vendor (libwvhidl, libwvdrmengine,
# liboemcrypto). A GSI therefore uses the *same* CDM, but the CDM asks Google's
# provisioning service for a certificate and only gets one when the build identity
# matches the certified device. A GSI presents something like
#   google/lineage_arm64_bgN/tdgsi_arm64_ab:14/...
# so provisioning is refused and it self-degrades to L3 (new System ID, 16 sessions,
# no HDCP). Rewriting the identity to the certified one restores L1, HDCP 2.3 and
# 50 sessions - verified on LineageOS 21 arm64_bgN (Android 14).
#
# IMPORTANT: ro.build.version.release and ro.build.type do NOT need to match stock.
# Presenting ":14" and "userdebug" still provisioned L1, which is what keeps
# `adb root` usable for the PairIP workaround. Only brand/device/name/model and the
# build id/incremental mattered.
#
# WHY debugfs AND NOT A MOUNT: Android system images are ext4 with the shared_blocks
# feature and are typically 100% full, so `mount -o rw` fails and
# `e2fsck -E unshare_blocks` cannot duplicate extents. debugfs can still replace a
# file in place, which is all we need.
#
# USAGE:
#   build/patch-gsi-identity.sh <system.img> [brand] [device] [build_id] [incremental]
# Defaults are this tablet's certified identity:
#   Lincplus / T3_US / TP1A.220624.014 / 20241016
#
# Run inside a container with e2fsprogs:
#   docker run --rm -v /path/to/project:/work debian:bookworm \
#     bash /work/build/patch-gsi-identity.sh /work/build/lineage-stockid.img

set -euo pipefail

IMG="${1:?usage: patch-gsi-identity.sh <system.img> [brand] [device] [build_id] [incremental]}"
BRAND="${2:-Lincplus}"
DEVICE="${3:-T3_US}"
BUILD_ID="${4:-TP1A.220624.014}"
INCREMENTAL="${5:-20241016}"

# Which props to fix. The three files matter because init resolves ro.product.* from
# the FIRST source in ro.product.property_source_order that defines it - on a GSI that
# is the product overlay baked into system.img, not the OEM product partition.
FILES="/system/build.prop /system/product/etc/build.prop /system/system_ext/etc/build.prop"

echo "== patching identity in $IMG"
echo "   brand=$BRAND device=$DEVICE build.id=$BUILD_ID incremental=$INCREMENTAL"

# Pull the current release string so the spoofed fingerprint stays self-consistent
# (we deliberately keep the GSI's own release/type).
TMP=$(mktemp -d)
for f in $FILES; do
    base=$(echo "$f" | tr '/' '_')
    debugfs -R "dump $f $TMP/$base" "$IMG" >/dev/null 2>&1 || { echo "   skip (absent): $f"; continue; }
    python3 - "$TMP/$base" "$TMP/$base.new" "$BRAND" "$DEVICE" "$BUILD_ID" "$INCREMENTAL" <<'PY'
import re, sys
src, dst, brand, device, build_id, incremental = sys.argv[1:7]
lines = open(src).read().splitlines(True)

release = next((l.split("=")[1].strip() for l in lines
                if l.startswith("ro.build.version.release=")), "14")
btype = next((l.split("=")[1].strip() for l in lines
              if l.startswith("ro.build.type=")), "userdebug")
tags = next((l.split("=")[1].strip() for l in lines
             if l.startswith("ro.build.tags=")), "release-keys")
fp = f"{brand}/{device}/{device}:{release}/{build_id}/{incremental}:{btype}/{tags}"

changed = []
for i, l in enumerate(lines):
    k = l.split("=")[0].strip()
    if re.match(r"^ro\.product\.(system|product|system_ext|vendor|odm)\.(brand|device|name|model)$", k):
        field = k.rsplit(".", 1)[1]
        val = brand if field == "brand" else device
        lines[i] = f"{k}={val}\n"; changed.append(k)
    elif k in ("ro.build.id",):
        lines[i] = f"{k}={build_id}\n"; changed.append(k)
    elif k in ("ro.build.version.incremental",):
        lines[i] = f"{k}={incremental}\n"; changed.append(k)
    elif re.match(r"^ro\.(system|product|system_ext|vendor|odm)\.build\.fingerprint$", k):
        lines[i] = f"{k}={fp}\n"; changed.append(k)

open(dst, "w").writelines(lines)
print(f"   {len(set(changed))} props rewritten -> {fp}")
PY
    debugfs -w -R "rm $f" "$IMG" >/dev/null 2>&1 || true
    debugfs -w -R "write $TMP/$base.new $f" "$IMG" >/dev/null 2>&1
done

echo "== verify"
for f in $FILES; do
    debugfs -R "cat $f" "$IMG" 2>/dev/null | grep -E "^ro\.(product\.(system|product|system_ext)\.(brand|device|name)|build\.id=|system\.build\.fingerprint=)" || true
done
rm -rf "$TMP"

echo "== done. Rebuild super with this system.img, flash, and check Widevine reads L1 / SysID 29739."
