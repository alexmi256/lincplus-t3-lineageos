# LineageOS on the LincPlus T3 (MT8781 / Helio G99)

Android 14 and Android 15 **GSI** builds for the LincPlus T3 (`T3_US`, MediaTek MT8781V/NA), with
**Widevine L1 preserved**, packaged as flashable `super.img` files.

This tablet has no kernel source, no device tree, no TWRP and no community. It cannot get a
device-specific ROM. It *is* fully Treble-compliant, so a Generic System Image works — and that is
what this project ships, together with the recipe to rebuild it yourself.

**Everything here was verified on real hardware**, including the parts that the internet says are
impossible (keeping Widevine L1 on a GSI).

---

## What you get

| Build | Android | LineageOS | Security patch | Signing | Widevine |
|---|---|---|---|---|---|
| **A15** (current) | 15 (SDK 35) | 22.2, `BP1A.250505.005` | 2026-11-01 | **release-keys** | **L1** |
| **A14** (fallback) | 14 (SDK 34) | 21.0, `UQ1A.240205.004` | 2026-11-01 | release-keys | **L1** |

Both include GApps (Play Store present), run on the stock vendor partition, and keep the bootloader
unlock's `orange` verified-boot state.

**Maturity:** both are fresh builds. A14 was run for about a day before the A15 work took over, so
neither has months of uptime behind it — see [`docs/16-field-test-results.md`](docs/16-field-test-results.md)
for exactly what has been tested and when.

Download links, sizes and SHA-256 sums: see [`artifacts/README.md`](artifacts/README.md).

---

## Before you start — the honest warnings

- **Unlocking the bootloader wipes the device** and permanently flips it to `orange`.
- **A `super` change requires a userdata wipe.** Skipping it can bootloop. `fastboot -w` from
  fastbootd silently skips userdata — use `fastboot erase userdata` (see
  [`docs/07-procedure.md`](docs/07-procedure.md)).
- **Partitions like `persist`, `nvram`, `nvdi` are device-unique.** Never restore another unit's
  readback. Back yours up first: [`docs/06-backup-and-risk.md`](docs/06-backup-and-risk.md).
- **Restoring stock needs SP Flash Tool on Windows** (or the OEM package). Keep that path working.
- No warranty, no support, no responsibility for bricked units. You need the OEM firmware package as
  your safety net before touching anything.

---

## Quick start

### Option A — flash a prebuilt image (no building)

```bash
# 1. verify what you downloaded
sha256sum super-lin22-signed.img            # compare with artifacts/README.md

# 2. unlock (once) — confirm the prompt on-screen with VOLUME UP within ~20s
fastboot flashing unlock

# 3. flash
fastboot flash super super-lin22-signed.img
fastboot flash vbmeta vbmeta-flags3.img     # Flags: 3 — required, or it will not boot
fastboot erase userdata
fastboot erase metadata
fastboot reboot
```

First boot takes 1–3 minutes. Full step-by-step, including fastbootd quirks:
[`docs/07-procedure.md`](docs/07-procedure.md).

### Option B — build it yourself

Prerequisites: Linux x86_64, Docker, **≥64 GB RAM**, **≥400 GB free SSD** (the tree is ~180 GB).
Total time ≈ 2–3 hours, mostly unattended.

```bash
scripts/01-build-toolchain.sh    # build the ubuntu:24.04 builder image
scripts/02-sync-source.sh        # repo init/sync lineage-22.2 (~180 GB)
scripts/03-build.sh              # lunch + make systemimage (~2 h)
scripts/05-package-super.sh      # patch identity + assemble super.img
```

Optional, for a shareable `release-keys` image:

```bash
scripts/make-certs.sh            # generate the 123 signing keys (once)
scripts/04-sign.sh               # target-files + otatools + sign_target_files.sh
```

The build environment is documented in
[`docs/13-docker-build-env-research.md`](docs/13-docker-build-env-research.md); the full build report
with timings and pitfalls is [`docs/14-build-report-2026-11-14.md`](docs/14-build-report-2026-11-14.md).

---

## Why this works at all

Two things make an up-to-date Android 15 possible on abandoned hardware:

1. **`lineage-22.2` is still alive.** LineageOS keeps merging Google's `android-security-15.0.0_rNN`
   tags into that branch and shipping 22.2 nightlies for devices that cannot move to 23.x. The
   *branch* was never dead — only the GSI distribution was. Details:
   [`docs/11-android15plus-outlook.md`](docs/11-android15plus-outlook.md).
2. **Widevine L1 is a build-identity problem, not a keybox problem.** The CDM lives only in `/vendor`
   and survives a GSI flash. It refuses to provision when the system claims to be a generic
   `lineage_gsi_arm64` device. Rewriting the identity props in three overlays restores L1 — no root,
   no Magisk, no keybox reprovisioning. Full mechanism and measurements:
   [`docs/10-widevine-l1-on-gsi.md`](docs/10-widevine-l1-on-gsi.md).

---

## What works / what doesn't

Verified = measured on hardware. Untested = nobody has tried it yet.
**Please run [`TESTING.md`](TESTING.md) and report results** — this table gets updated from real
device reports.

| Area | Status |
|---|---|
| Boot, Android 15, GApps, Play Store app installed | ✅ verified |
| Widevine L1 (SysID 29739, HDCP 2.3, 50 sessions) | ✅ verified |
| `ro.build.tags=release-keys`, self-signed system | ✅ verified |
| Security patch 2026-11-01 | ✅ verified |
| DRM Info, screenshots, launcher, setup wizard | ✅ verified |
| **Wi-Fi** | ✅ verified (connects, stable) |
| **Camera — rear and front** | ✅ verified (preview + stills) |
| **Audio — speaker** | ✅ verified |
| **Bluetooth** | 🟡 enumerates nearby devices; pairing / A2DP audio not yet confirmed |
| **Brightness** | 🟡 slider works, but the **lower third has little or no effect** — `GSI settings` brightness tweaks did not change it |
| Video recording | ⚠️ untested |
| Audio — headphone jack, USB-C, mic | ⚠️ untested |
| Sensors: accelerometer, gyro, light, proximity | ⚠️ untested |
| Auto-rotate | ⚠️ untested |
| Hardware video decode (H.264/HEVC/VP9) | ⚠️ untested — codec list reported by the build looks complete |
| Encryption / FBE | ✅ enabled (`ro.crypto.state=encrypted`), full reboot cycle untested |
| MTP / USB file transfer | ⚠️ untested |
| Battery / sleep behaviour | ⚠️ untested |
| Widevine L3 apps that pin hardware | ⚠️ untested |
| Play Integrity DEVICE/STRONG | ❌ expected to fail (unlocked bootloader, custom ROM) |
| Play Protect "certified" banner | ❓ test it — register GSF ID if it complains |
| Android 16+ | ❌ blocked by vendor API level 31 (needs `202404`) |

Legend: ✅ verified on hardware · 🟡 partially working / partially tested · ⚠️ untested · ❌ known not
to work. "Verified" means one unit, one report — this is a small project, not a QA lab. Run
[`TESTING.md`](TESTING.md) and open an issue to move rows. The raw report behind the ✅ rows is in
[`docs/16-field-test-results.md`](docs/16-field-test-results.md).

**Known issue — minimum brightness.** The bottom third of the brightness curve does very little, so
the screen does not get as dim as stock. Toggling the GSI brightness settings under
Settings → Phh Treble Settings did not help. Practical workarounds are a dimming overlay app or
Night Light; a proper fix would need a device tree (the backlight is controlled through the vendor
HAL, not something the GSI can recalibrate).


Known limitations by design:

- `ro.adb.secure=0` — the image ships with **unauthenticated ADB**, inherited from the GSI tooling.
  Anyone with a cable gets a shell and `adb root`. See [`docs/14-build-report-2026-11-14.md`](docs/14-build-report-2026-11-14.md).
- Signed (`release-keys`) and test-keys images cannot be mixed without a wipe.
- Fingerprint string stays generic (`lineage_gsi_arm64_gN`) even though the device identity props read
  `Lincplus/T3_US/T3_US`. The CDM accepts this; Play Integrity does not.

---

## Repository layout

```
docs/          18 documents: device profile, partition map, procedure, findings, measurements
research/      sourced deep-dive reports the docs were built from
scripts/       docker build pipeline, Widevine patcher, super assembler, cert generator
artifacts/     download instructions, sizes, checksums, GitHub release limits
TESTING.md     the checklist to run on your unit
```

Start with [`docs/01-device-profile.md`](docs/01-device-profile.md) for what the hardware is, and
[`docs/07-procedure.md`](docs/07-procedure.md) for the actual flashing sequence.

---

## Contributing / reporting

Test results, failures and device variants are genuinely useful — open an issue with the output of
`TESTING.md` filled in. If you have a sibling device on the same board (`tb8781p1_64_wifi`), that is
especially interesting.
