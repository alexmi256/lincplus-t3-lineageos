# Android 15+ outlook for this tablet

Research note, 2026-11-13. Question: what breaks on Android 15 and newer GSIs, and would any of it
affect the Lincplus T3 (`MT8781` / Helio G99, vendor **API level 31**, kernel 5.10.209, 8 GB).

## The limiting factor is the vendor API level, not the Android version

Since **Android 14 QPR3** Google decoupled the vendor API level from the SDK level and switched it
to a `YYYYMM` date format. The boot-time compatibility check compares the GSI's expectation against
`ro.vendor.api_level` / `ro.board.api_level` and blocks the boot if the vendor is too old.

| GSI | Minimum vendor API level | Our device (`31`) |
|---|---|---|
| Android 14 | 30 (integer scheme) | ✅ boots (verified) |
| Android 15 | 30 (integer scheme) | ✅ should boot |
| Android 16 | **`202404`** (`YYYYMM`) | ❌ blocked by the compatibility check |

`31` cannot ever satisfy `202404` — it is a different numbering scheme, and this OEM shipped an
Android 12 vendor partition that will never be updated. So **Android 15 is the ceiling for official
GSIs on this tablet**; Android 16+ needs either a community build with the compatibility shims
restored, or a device-specific ROM with its own vendor.

## What actually changed in Android 15 that matters here

1. **VNDK deprecation.** VNDK is deprecated from Android 15 and Android 16 relies on LLNDK +
   AIDL HALs. Our vendor partition is a legacy VNDK build. Android 15 still carries the
   compatibility path; Android 16 does not, which is the same wall as the API-level check.
2. **Minimum installable app target.** From Android 15, apps targeting API < 24 cannot install.
   Irrelevant here — the DRM Info APK used for measurement targets API 37 and its `minSdk` is 32.
3. **16 KB page size.** Introduced as an option in Android 15 for *new* devices. Our kernel is a
   4 KB-page 5.10 build; this affects app alignment for 16 KB devices, not whether a 4 KB GSI boots.
4. **Nothing in the A/B, `super`, or AVB path changed** relative to Android 14. The recipe already
   proven here (custom `super` + `vbmeta` with `Flags: 3`) carries over unchanged.

## GSI availability, as of this research

**Android 15 / LineageOS 22.2**

- **Andy Yan's tree does contain 22.2** — `lineage-22-light/` holds exactly two files, both dated
  **2025-06-22**:
  - `lineage-22.2-20250621-UNOFFICIAL-gsi_arm64_vN.img.gz` (1.1 GB) — vanilla, no superuser
  - `lineage-22.2-20250621-UNOFFICIAL-gsi_arm64_gN-signed.img.gz` (1.4 GB) — GApps, no superuser,
    signed with maintainer keys

  So 22.2 is not "missing", but it is **frozen**: that directory has not changed since 2025-06-22,
  while the same project's Android 14 line shipped `lineage-21.0-20261108` on **2026-11-12**. The
  22.x line is retired in practice, which is consistent with the DISCONTINUED tag on the XDA
  thread. Layered "Light" builds carry the minimal patchset, not a full LineageOS device tree.
- **Actively maintained alternative: Marinov's LineageOS 22.2 "Light"** (XDA thread active to
  Oct 2025, builds via a OneDrive folder linked there). Note it is vanilla — bring your own GApps.
- **MisterZtr-GSI** publishes both an Android 15 folder *and*, as of 2026-05-24, LineageOS **23.2
  (Android 16)** GAPPS EROFS builds. Android 16 is the one that hits the vendor-API wall below.

**Naming rules** (from the project README, matters when picking a file):
`{arch}_{a|b}{v|g}{N|S}-{signed|vndklite|personal}` — `b` = A/B, `g` = regular GApps, `v` = vanilla,
`N` = no superuser, `signed` = maintainer keys. Our A14 image was `arm64_bgN`; the 22.2 files omit
the `b` because that line ships A/B only.

Helio G99 is not exotic for GSIs — owners of other G99 tablets (e.g. Alldocube iPlay 60 mini Pro)
report running LineageOS via GSI, consistent with what this device already does on Android 14.


## Why "LineageOS stopped Android 15" is three different statements

**1. Official LineageOS did NOT stop supporting Android 15.** From LineageOS Changelog 32
(2026-10-11), verbatim:

> "LineageOS 22.2 still supports many devices running `4.4` and `4.9`, and will continue to receive
> builds and security patches merged monthly **until Google stops distributing official
> security-bulletins for Android 15** — and you can still submit new LineageOS 22.2 devices for
> official builds!"

So 22.2 is a live legacy branch, not a dead one. What happened is that it stopped being one of the
*two current* releases: LineageOS supports the two latest branches simultaneously, and those are now
**23.2 (Android 16 QPR2)** and **24.0 (Android 17)**. Changelog 32 also states they will only accept
22.2 submissions for 4.4/4.9-kernel devices, because those legacy kernels carry "countless platform
commits that are rather hacky and difficult to continue to pull forward".

**2. Android 15 itself has not stopped receiving updates.** Same changelog, on security patches:

> "we will merge full security bulletins and change the security patch level string to match on all
> branches that Google actively distributes bulletins for — which as of writing is **Android 14
> (LineageOS 21) and newer**."

Android 15 is inside that window. Google is still publishing bulletins for it, so 15 is a supported
release, not EOL.

**Evidence that 22.2 is not merely "supported on paper"** — the download server was serving 22.2
nightlies at the time of writing:

| Device | Latest 22.2 build |
|---|---|
| `taimen` (Pixel 2, kernel 4.4) | `lineage-22.2-20261112-nightly-taimen-signed.zip` |
| `walleye` (Pixel 2, kernel 4.4) | `lineage-22.2-20261113-nightly-walleye-signed.zip` |

Both are 4.4-kernel devices that cannot move to 23.x, which is exactly the carve-out Changelog 32
describes. So the branch is genuinely alive: monthly ASB merges land in git **and** signed artefacts
ship continuously. What LineageOS does not publish — and never has — is a **GSI**; their release model
is per-device. That, plus Andy Yan freezing his GSI directory in June 2025, is why the version *looks*
abandoned from a GSI consumer's viewpoint.


**3. What actually stopped is Andy Yan's *GSI build* of 22.2** — a different thing again. His
`lineage-21` (Android 14) tree shipped `lineage-21.0-20261108` on 2026-11-12, while `lineage-22-light`
has been untouched since 2025-06-22. **No public statement from him explaining the stop was found**;
that is a maintainer decision, not a LineageOS or Google policy. Treat any explanation you see for it
as inference rather than fact.

## Practical consequence, and it inverts the usual assumption

A "newer Android" is not automatically a newer *security* posture here:

| Build | Android | Security patch level |
|---|---|---|
| `lineage-21.0-20261108` (already flashed, working, L1) | 14 | **2026-11-01** |
| `lineage-22.2-20250621` (Android 15 GSI) | 15 | ~2025-06 |
| Marinov 22.2 (latest seen, Oct 2025) | 15 | ~2025-10 |

Upgrading to the Android 15 GSI would move *backwards* about 17 months on security patches while
gaining Android 15. For a tablet whose main job is media playback, staying on the current A14 build
is the stronger position — and it is also the one already proven to keep Widevine L1.


## Prediction for this tablet

| Version | Expected outcome | Basis |
|---|---|---|
| Android 15 | **boots**, same flashing recipe; Widevine L1 needs the identity patch re-applied | vendor 31 ≥ requirement; A14 already works identically |
| Android 16+ | **blocked** by `ro.vendor.api_level` < `202404` | documented compatibility gate; vendor will never update |

Worth verifying rather than assuming: diff a LineageOS 22 image for the same three identity files
(`/system/build.prop`, `/system/product/etc/build.prop`, `/system/system_ext/etc/build.prop`) — the
Widevine fix from `10-widevine-l1-on-gsi.md` should port, but the prop layout must be re-checked
rather than assumed, and `patch-gsi-identity.sh` reads the release/type from whichever image it is
given, so it adapts.

Cheapest way to test Android 15 without committing: build `super` with the A15 system image, keep
`super-new`/`super-stockid` on disk, and roll back the same way we already have three times.

## Not worth attempting

Android 16+ on the stock vendor partition. Even with the API-level check patched out, a 2026 system
image against a 2022 VNDK vendor is the exact combination that produces half-broken HALs (camera,
codecs, telephony) rather than a usable tablet.
