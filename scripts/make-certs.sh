#!/bin/bash
# Container-side helper: generate the release signing keys.
#
# Produces ~/.android-certs with the standard certs plus one key per APEX/CAPEX that
# sign_target_files.sh references (123 names in total at the time of writing).
#
# NOTE: keys.sh exits non-zero at the end because the template ships a pre-existing
# releasekey that make_key refuses to overwrite. All keys are still generated.
set -u
SRC="${SRC:-/srv/src}"
CERTS="${CERTS:-/srv/home/.android-certs}"

cd "$SRC" || exit 1

existing=$(ls -1 "$CERTS"/*.pk8 2>/dev/null | wc -l)
if [ "$existing" -gt 100 ]; then
    echo "certs already present ($existing keys) - nothing to do"
    exit 0
fi

echo "== generating keys from lineage/scripts/lineage-priv-template"
rm -rf vendor/lineage-priv
cp -r lineage/scripts/lineage-priv-template vendor/lineage-priv
( cd vendor/lineage-priv && ./keys.sh > /tmp/keys.log 2>&1 ) || true
grep -ciE "error" /tmp/keys.log 2>/dev/null | sed 's/^/  keys.sh error lines: /'

mkdir -p "$CERTS"
cp -f vendor/lineage-priv/*.pk8 vendor/lineage-priv/*.x509.pem "$CERTS"/ 2>/dev/null || true
cd "$CERTS" || exit 1
ln -sf releasekey.pk8 testkey.pk8
ln -sf releasekey.x509.pem testkey.x509.pem

echo "== filling any names the signing script expects"
grep -oE '\$HOME/\.android-certs/[A-Za-z0-9._]+' \
     "$SRC/lineage_build_unified/sign_target_files.sh" 2>/dev/null \
  | sed 's#.*android-certs/##' | sort -u > /tmp/want.txt

missing=0
while read -r n; do
    [ -f "$CERTS/$n.pk8" ] && continue
    ( cd "$SRC/vendor/lineage-priv/keys" && ./make_key.sh "$n" 4096 >/dev/null 2>&1 )
    if cp -f "$SRC/vendor/lineage-priv/keys/$n.pk8" \
             "$SRC/vendor/lineage-priv/keys/$n.x509.pem" "$CERTS"/ 2>/dev/null; then
        missing=$((missing+1))
    fi
done < /tmp/want.txt

rm -rf "$SRC/vendor/lineage-priv"

echo "generated extra keys: $missing"
echo "total keys in $CERTS: $(ls -1 "$CERTS"/*.pk8 2>/dev/null | wc -l)"
echo
echo "BACK THIS DIRECTORY UP. If you lose it you cannot update your own builds without a wipe."
