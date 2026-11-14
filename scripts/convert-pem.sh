#!/bin/bash
# Container-side helper: make_key emits .pk8 (DER) + .x509.pem (certificate), but
# sign_target_files_apks passes a *PEM private key* for APEX payload signing
# (--extra_apex_payload_key ...=$HOME/.android-certs/<name>.pem).
#
# Without this step signing dies with:
#   avbtool: Error getting public key: Could not open file ... com.android.adbd.pem
set -u
CERTS="${CERTS:-/srv/home/.android-certs}"

converted=0
for f in "$CERTS"/*.pk8; do
    [ -e "$f" ] || continue
    base="${f%.pk8}"
    [ -f "$base.pem" ] && continue
    if openssl pkcs8 -in "$f" -inform DER -nocrypt -out "$base.pem" 2>/dev/null; then
        converted=$((converted+1))
    fi
done

echo "converted to .pem: $converted"
echo "pem private keys now: $(ls -1 "$CERTS"/*.pem 2>/dev/null | grep -vc '\.x509\.pem$')"
