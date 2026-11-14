#!/bin/bash
# Split a large image into GitHub-release-sized parts, with a checksum manifest.
#
#   scripts/split-for-release.sh super-lin22-signed.img [chunk-size]
#
# GitHub caps a release asset at 2 GiB. Default chunk is 1900 MiB to stay safely under it.
set -eu
FILE="${1:?usage: $0 <image> [chunk-size like 1900M]}"
CHUNK="${2:-1900M}"

[ -f "$FILE" ] || { echo "ERROR: $FILE not found" >&2; exit 1; }

rm -f "$FILE".part-*
echo "== splitting $FILE into ${CHUNK} parts"
split -b "$CHUNK" -d -a 2 "$FILE" "$FILE.part-"

echo "== checksums"
sha256sum "$FILE" | tee "$FILE.sha256"

echo
echo "== parts"
ls -lh "$FILE".part-* | awk '{print "  "$9"  "$5}'
echo
echo "Upload every part plus $FILE.sha256 as release assets."
echo "Users rejoin with:"
echo "  cat $(basename "$FILE").part-* > $(basename "$FILE")"
echo "  sha256sum -c $(basename "$FILE").sha256"
