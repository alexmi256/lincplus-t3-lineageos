# Build report — LineageOS 22.2 GSI, first full build

Date: 2026-11-14. Host: `build-host` (Ryzen 9 5900X, 62 GiB, container `los22-builder`).
Build log: `~/build/logs/build-20261114-0602.log` (28 MB).

## Result

| | |
|---|---|
| Outcome | **success**, `BUILD_EXIT=0`, "#### build completed successfully" |
| Wall clock | **2:06:38** (128 min), 180,673 ninja targets |
| Output | `~/build/home/build-output/lineage-22.2-20261114-UNOFFICIAL-gsi_arm64_gN.img`, 3.0 GB |
| Tree | 189 GB after sync (HEAD of `lineage-22.2`) |
| Patches | 78 applied, **1 failed** (see below) |
| Signing | skipped — no `$HOME/.android-certs`, as planned |

## The one failed patch — harmless for this device

```
Applying: Remove debuggable requirement for signature spoofing
error: patch failed: services/core/java/com/android/server/pm/ComputerEngine.java:1493
Patch failed at 0001 Remove debuggable requirement for signature spoofing
```

- Part of **`patches_platform`**, applied at log line 64 (before the treble group at 139).
- It is the **microG signature-spoofing enabler** — it relaxes the check that an app requesting
  signature spoofing must be debuggable. We do not use microG, so its absence changes nothing for
  this tablet.
- Cause: `ComputerEngine.java` has drifted in `lineage-22.2` since the patch was written against the
  2025-06-21 tree. Classic patch drift — exactly the risk flagged in `12-gsi-build-handoff.md` §8.
- The tree was **not** left mid-`git am`: `frameworks/base` is clean and no `.git/rebase-apply`
  exists. The build continued and completed.
- If it ever matters: rebase that single patch, or run the build with the microG patches omitted.

## The six "Java parsing error" lines — by design, not a defect

Example:

```
Code processing error in frameworks/base/services/core/java/com/android/server/wm/DesktopModeBoundsCalculator.java:128:
  Java parsing error: (line 128,col 74) Parse error. Found  "yield" <IDENTIFIER>, expected one of  "}"
```

- Produced by **`protologtool`** (`frameworks/base/tools/protologtool`), the ProtoLog source
  generator — *not* by `javac`. Its parser (`StaticJavaParser`, language level `RAW`) is older than
  the Java syntax in the tree, so it trips on `yield`, lambdas in parens, etc.
- The tool reports through an injector callback (`ProtoLogTool.kt:494`, `reportParseError`) that
  **prints the message and continues**. It never affects the build result.
- Effect: ProtoLog statements in those 6 files are skipped when generating the log schema. ProtoLog
  is developer tracing only; no runtime behaviour for a user device changes.

**Verdict: benign. 0 ninja failures, build exit 0.**

## Comparison against Andy Yan's official 22.2 GSI (20250621)

Note: LineageOS does not publish GSIs at all, so Andy Yan's `gN`-signed build is the closest thing to
an "official 22.2 GSI" that exists.

| Property | Andy 20250621 (ref) | Ours 20261114 |
|---|---|---|
| File size | 2.9 GB | 3.0 GB |
| ext4 blocks × 4096 | 744,075 | 750,258 |
| Inode count | 8,464 | 8,832 |
| ext4 features | identical set | identical set |
| `ro.build.id` | BP1A.250505.005 | **BP1A.250505.005** (same) |
| `ro.build.version.release` / sdk | 15 / 35 | 15 / 35 |
| **`ro.build.version.security_patch`** | **2025-06-01** | **2026-11-01** |
| `ro.build.type` | userdebug | userdebug |
| `ro.build.tags` | **release-keys** | **test-keys** |
| `ro.build.date` | 2025-06-21 CST | 2026-11-14 UTC |
| `system/app` dirs | 23 | 23 (identical set) |
| `system/priv-app` dirs | 43 | 43 (identical set) |
| GApps in `product/priv-app` | 3 | 3 |
| GApps in `product/app` | 1 | 1 |
| `system_ext/app` count | 6 | 6 |

Interpretation:

1. **The rebuild works**: same AOSP tag, same app inventory, same GApps layout, same ext4 geometry
   class. The +6,183 blocks / +368 inodes are consistent with five months of merged changes.
2. **The security bump is real at the metadata level**: SPL moved 2025-06 → 2026-11 while the AOSP tag
   stayed `BP1A.250505.005`. That is exactly the mechanism described by LineageOS Changelog 32 —
   bulletins merged into the existing QPR2 branch, SPL string advanced to match.
3. **`test-keys` is the one material difference**, caused by not signing. See the risk note below.

## Risk flagged before flashing: `test-keys` and Widevine

The A14 image that held Widevine **L1** was Andy's **`-signed`** build (`release-keys`). This build is
unsigned (`test-keys`). The identity-spoofing fix rewrites the *fingerprint* (which ends in
`release-keys`), but `ro.build.tags` itself remains `test-keys` — and the Widevine provisioning path
may read that property.

Two ways to de-risk, in order of cheapness:

1. **Flash and measure** (≈10 min/flash). If it reports L3, extend `patch-gsi-identity.sh` to also set
   `ro.build.tags=release-keys` in the three prop files and reflash. That is consistent with the
   existing approach: the CDM was shown to gate on build identity, not on cryptographic signing.
2. **Sign the build properly** — generate `.android-certs`, run `sign_target_files.sh`, rebuild
   (~1 h). Reproduces Andy's configuration exactly, no property fudging.

Recommendation: option 1 first, because it is measurable and reversible; option 2 only if the
property patch proves insufficient.

## Boot test — 2026-11-14, unit SERIAL-TEST

**Correction to an earlier reading in this report:** the first A15 flash used `fastboot -w` from
fastbootd, which printed only `partition not found: cache/metadata` and **silently skipped userdata**.
The boot was therefore *dirty* — proven afterwards by `firstInstallTime=2026-11-13` on a sideloaded app
that had survived. (An earlier `ls /data/app | wc -l` → 0 was a permissions artefact: `shell` cannot
read `/data/app`.) `fastboot erase userdata` from fastbootd **does** work and reports `OKAY`.

Final flashing sequence used, which is the one to keep:

```bash
fastboot flash super build/super-lin22-stockid.img
fastboot erase userdata
fastboot erase metadata
fastboot reboot
```

Verified clean afterwards: `settings get secure user_setup_complete` → **0**, and the sideloaded app
was gone.

| Result | Value |
|---|---|
| Boot | **success** — adb up in ~50 s |
| Version | **15 / SDK 35** |
| Build | `BP1A.250505.005`, `ro.build.date` 2026-11-14 |
| Security patch | 2026-11-01 |
| Brand | **Lincplus** (identity patch applied) |
| Build tags | `test-keys` |
| verified boot | `orange`, `flash.locked 0` |
| UI | Android 15 home screen, Google search widget present (GApps working) |
| **Widevine** | **L1, System ID 29739, HDCP 2.3, 50 sessions** |

Images produced:

| Artefact | Purpose |
|---|---|
| `build/lineage-22.2-20261114-gsi_arm64_gN.img` | raw build output, identity untouched (L3) |
| `build/lineage-22.2-stockid.img` | same, identity-patched (3,122,413,568 B) |
| `build/super-lin22-stockid.img` | **the good A15 + L1 flashable `super`** (9.0 GB) |
| `build/super-lin22.img` | first A15 `super`, unpatched identity |
| `build/super-stockid.img` | A14 + L1 fallback (9.0 GB) |

**Is another build needed?** No. SPL 2026-11-01 is the current Android security bulletin; `lineage-22.2`
HEAD was synced the same day. A rebuild would only add LineageOS commits made after 2026-11-14 — no new
security content until the December bulletin. Rebuilding becomes worthwhile only to (a) sign the image
(`release-keys`, needed for Play Integrity, not for Widevine) or (b) pick up upstream changes.

Flashed from the Hermes host, not from `build-host`: the tablet is attached to the Hermes host's USB
bus (`adb devices` → `SERIAL-TEST`), and `build-host`'s `lsusb` shows no MediaTek device. The image
was copied over the LAN (3 GB) before flashing.


## Release-keys build — 2026-11-14

Built, patched and flashed a **`release-keys` signed** variant, because the image is to be shared and
some consumers require a non-testkey ROM.

### Key generation

`sign_target_files.sh` references **123 distinct key names** (12 standard certs + one per APEX/CAPEX).
Generated with the tree's own official generator rather than by hand:

```bash
cp -r lineage/scripts/lineage-priv-template vendor/lineage-priv/keys
cd vendor/lineage-priv/keys && ./keys.sh     # standard certs @2048, APEX/CAPEX @4096, plus avb
# then copy into ~/.android-certs and link testkey -> releasekey
```

Result: **211 files / 211 keys** in `~/.android-certs`, all 123 expected names present. `keys.sh` exits
non-zero at the end because the template ships a pre-existing `releasekey` that `make_key` refuses to
overwrite — cosmetic, all keys still generate.

### Two pitfalls, both silently fatal

1. **`avbtool` needs a PEM private key for APEX payload signing.** `make_key` emits `.pk8` (DER) and
   `.x509.pem` (certificate) only, while `sign_target_files_apks` passes
   `--extra_apex_payload_key ...=$HOME/.android-certs/<name>.pem`. Without the `.pem`, signing dies at
   the first APEX:
   `avbtool: Error getting public key: Could not open file ... com.android.adbd.pem`.
   Fix: convert every key —
   `openssl pkcs8 -in <name>.pk8 -inform DER -nocrypt -out <name>.pem` (211 conversions).
2. **`set -u` breaks `source build/envsetup.sh`**, which makes `lunch` silently unavailable
   (`lunch: command not found`). Keep the wrapper free of `set -u`.

Because `systemimage` and `target-files-package` had already completed, only the signing pass had to be
re-run — a ~10 minute step, not a rebuild.

### Verification

| Check | Result |
|---|---|
| `/system/etc/security/otacerts.zip` | contains `releasekey.x509.pem` (was `testkey.x509.pem`) |
| `ro.build.tags` | **`release-keys`** |
| `ro.build.version.security_patch` | 2026-11-01 |
| `ro.build.type` | `userdebug` (keeps `adb root`) |
| Boot after flash + `erase userdata` | success, `setup_complete=0` |
| Brand | `Lincplus` (identity patch applied) |
| **Widevine** | **L1, System ID 29739, HDCP 2.3, 50 sessions, CDM 16.1.1@006, OEM Crypto 16** |

Signed image sha256 prefix `075e40a8…`, `super-lin22-signed.img` 9.0 GB.

Note the CDM accepts this build even though `ro.build.fingerprint` still reads the generic
`lineage_gsi_arm64_gN` string — consistent with the Android 15 finding in
`10-widevine-l1-on-gsi.md`: the gate is the resolved identity props, not the fingerprint literal.

### Artefacts now on disk

| File | Purpose |
|---|---|
| **`super-lin22-signed.img`** (9.0 GB) | **release-keys A15 + L1 — the shareable image** |
| `lineage-22.2-signed-stockid.img` (3.0 GB) | its patched system image |
| `lineage-22.2-signed.img` (3.0 GB) | signed, identity untouched |
| `super-lin22-stockid.img` (9.0 GB) | test-keys A15 + L1 (previous build) |
| `super-stockid.img` (9.0 GB) | A14 + L1 fallback |

## What the base actually is, and how it stays current

No prebuilt image was used. The base is a **source tree**, and that distinction is what makes a
current Android 15 build possible while Andy Yan's binary is frozen at 2025-06-21.

### The base

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
```

- `lineage-22.2` is LineageOS' **Android 15 QPR2** branch. The tree's own
  `vendor/lineage/vars/aosp_target_release` reads **`bp1a`**, which is what the lunch target uses.
- Synced at HEAD on **2026-11-14**. The manifest repo's most recent commit was
  `353894c 2026-10-14 manifest: Track forks for 2026-11 ASB` — i.e. the tree we built *is* the
  November 2026 Android Security Bulletin state.

### How it stays current

LineageOS keeps merging Google's `android-security-15.0.0_rNN` tags into `lineage-22.2` long after
Android 15 stopped getting feature releases, and re-points the manifest at its own forks each month.
Visible in the manifest history:

```
353894c 2026-10-14  manifest: Track forks for 2026-11 ASB      <- what we built
98c181d 2026-09-18  manifest: Forks for android-security-15.0.0_r17
52602ac 2026-08-26  Track our own forks for 2026-09 ASB patching
14bc77e 2026-05-25  manifest: Track forks for 2026-06 ASB
05212dd 2025-12-04  manifest: December 2025 Security Update
```

and in `build/make`:

```
f9262a98c4 2025-09-03  Merge tag 'android-security-15.0.0_r10' into staging/lineage-22.2_merge-...
```

**Why the platform build ID never moves:** Android 15's last feature release was QPR2, so the AOSP
platform ID stays `BP1A.250505.005`. Security tags change the **SPL string only**. That is exactly
what the comparison against Andy Yan's image showed — same `ro.build.id` (`BP1A.250505.005`), SPL
moved 2025-06-01 → 2026-11-01.

### The GSI layer on top

The LineageOS tree alone builds devices, not GSIs. Andy Yan's `lineage-22-light` tooling supplies:

1. `local_manifests_treble/manifest.xml` → adds `android_device_lineage_gsi` (`lineage-22`) plus vendor
2. `repopick` of three Gerrit changes (notification behaviour)
3. `patches_platform` + `patches_treble` — **78 patches applied, 1 rejected as already-upstream**
4. `lunch lineage_gsi_arm64_gN-bp1a-userdebug` → `make installclean` → `make systemimage`

### Our layer on top of that

| Step | What it adds |
|---|---|
| `patch-gsi-identity.sh` | stock build identity in three prop overlays → Widevine L1 |
| `sign_target_files.sh` + our keys | `release-keys` instead of AOSP testkey |
| `make-super.sh` | OEM `vendor`/`product` + our `system_a` into a flashable 9 GB `super` |

## Google Play: what signing does and does not fix

Play Store is already present and current on this build — `com.android.vending` **41.9.17**, plus
`com.google.android.gms` and `com.google.android.gsf`. **Test-keys do not prevent Play Store from
running or installing apps.**

Three separate things get confused here:

| Layer | What decides it | Does our signing key matter? |
|---|---|---|
| Play Store app works | GApps present in the image | **No** |
| Device certification ("Play Protect certified") | GSF ID registered against Google's certified list | **No** |
| Play Integrity verdicts (banking, Netflix, some games) | props + boot state + **ROM signing key** + hardware attestation | **Partly** |

Measured on the built image: `/system/etc/security/otacerts.zip` contains exactly one certificate,
`testkey.x509.pem`, subject `CN=Android, O=Android`, SHA-256
`A4:0D:A8:0A:59:D1:70:CA:A9:50:CF:15:C1:8C:45:4D:47:A3:9B:26:98:9D:8B:64:0E:CD:74:5B:A7:1B:F5:DC`
— i.e. the AOSP testkey. That is precisely the condition the Play Integrity community flags as one
blocker for the DEVICE verdict on custom ROMs.

But it is only one input. This device is also bootloader-unlocked (`orange`), runs a generic GSI
fingerprint, and has no Google-signed hardware attestation key. Re-signing removes one blocker of
four; DEVICE/STRONG verdicts would almost certainly still fail.

### Cost of moving off test-keys

Per the LineageOS signing guide, roughly **2–3 hours, mostly unattended**:

1. **Generate keys once** (~10 min): `~/.android-certs` with the 12 standard certs via
   `./development/tools/make_key`, plus `testkey` symlinks to `releasekey`, plus **APEX keys** —
   LineageOS 19.1+ requires `SHA256_RSA4096` for APEX, which needs a patched copy of `make_key`
   (`sed -i 's|2048|4096|g'`). Andy's `build_unified.sh` keys off `$HOME/.android-certs`, so this
   manual layout fits the existing script without modification.
2. **Rebuild with signing** (~45–75 min): the script already contains the branch — when
   `.android-certs` exists and the target ends in `_g?`, it runs `make target-files-package otatools`
   then `sign_target_files.sh $OUT/signed-target_files.zip` and extracts the signed `system.img`.
3. **Repackage and reflash** (~10 min): `make-super.sh` with the signed image, flash, wipe.

Key-change rules simplify here: switching test-keys → release-keys normally needs a migration build to
avoid a data wipe, but we wipe on every `super` change anyway, so that step is moot.

### Recommendation

Try the current build in Play first. Signing does not gate Store access, and the certification banner
(if it appears) is fixed by registering the **GSF ID** at `google.com/android/uncertified` — which
requires signing into Play once so the ID exists, then reading it from
`/data/data/com.google.android.gsf/databases/gservices.db` (the `android_id` row; the DB is empty until
first sign-in, verified). Sign the ROM only if a specific app refuses to run *because of* the ROM key,
or if you want future updates signed with keys you control.


## Unauthenticated ADB is baked into these images (worth knowing before daily use)

After the clean wipe — no developer options, no adb authorization — `adb install` and `adb root` still
worked. Cause, verified on the device and in the build:

| Property / flag | Value |
|---|---|
| `ro.build.type` | `userdebug` |
| `ro.debuggable` | `1` |
| **`ro.adb.secure`** | **`0`** |
| `persist.sys.usb.config` | `adb` |
| `adb_enabled` / `development_settings_enabled` | `1` / `1` |

`build_unified.sh:112` builds with **`WITH_ADB_INSECURE=true`**, which is what sets `ro.adb.secure=0`.
Combined with a `userdebug` image, `adbd` starts at boot and accepts **any** USB client with no key and
no prompt — so there was nothing to enable and nothing to approve.

This is inherent to Andy Yan's "Light" GSIs, not something introduced by our rebuild: the A14 image carries the same pair (`ro.debuggable=1`, `ro.adb.secure=0`).

Implication: on this image, anyone with a cable and physical access gets a shell, and `adb root` is
available. For a test unit that is convenient; for a carried daily driver it is a real exposure.

Mitigations, cheapest first:

1. **Right now, on the device:** `settings put global adb_enabled 0` (and optionally
   `setprop persist.sys.usb.config mtp`). Reversible from Developer options.
2. **Proper fix:** patch `build_unified.sh` to drop `WITH_ADB_INSECURE=true` (lines 112 and 116), rebuild
   → `ro.adb.secure=1`, so authorization is required again. `adb root` keeps working because that is
   gated on `ro.debuggable=1`, not on the secure flag. Cost: one rebuild.

## The microG patch failure — resolved, and it is good news

The patch is **obsolete**. `frameworks/base` already contains the identical change:

```
6e1c45fb8edb 2024-03-17 Remove debuggable requirement for signature spoofing
```

That is the same commit subject as the patch, already merged upstream in LineageOS. The current code
has no `isDebuggable()` guard left to delete, which is exactly why `git am` rejected it. Nothing is
missing from the build.

Current `ComputerEngine.isMicrogSigned()` on `lineage-22.2`:

```java
public static boolean isMicrogSigned(AndroidPackage p) {
    // Allowlist the following apps:
    // * com.android.vending - microG Companion
    // * com.google.android.gms - microG Services
    if (!p.getPackageName().equals("com.android.vending") &&
            !p.getPackageName().equals("com.google.android.gms")) {
        return false;
    }
    return Signature.areExactMatch(
            p.getSigningDetails(), new Signature[]{MICROG_REAL_SIGNATURE});
}
```

So signature spoofing is available **with no patching**, subject to two constraints that matter in
practice:

1. Only `com.android.vending` and `com.google.android.gms` are eligible — the standard microG package
   pair.
2. The APK must be signed with **`MICROG_REAL_SIGNATURE`**, i.e. the official microG signing key.
   Third-party microG repacks (MinMicroG, microG-RE, self-built) carry different signatures and will
   *not* match without a further patch to relax that comparison.

Conclusion: keep the official microG builds and nothing else is needed.

## Reproducing this build

```bash
ssh user@BUILD-HOST-IP
docker run --rm -it -v ~/build/src:/srv/src -v ~/build/ccache:/srv/ccache \
  -v ~/build/home:/srv/home los22-builder bash
# inside:
export HOME=/srv/home && cd /srv/src
bash lineage_build_unified/build_unified.sh treble 64GN      # add `nosync` to skip re-sync + patches
```

A warm-cache rebuild should be considerably faster than 128 minutes.
