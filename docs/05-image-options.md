# GSI image options for this tablet

## What the image must be

| Requirement | Value | Why |
|---|---|---|
| Architecture | **arm64** (`arm64-v8a`) | `ro.product.cpu.abi` |
| Binder / partition layout | **`b`** (A/B-capable) | `ro.build.ab_update=true`, dynamic `super` |
| GApps | your choice — but see below | stock has Play Store; pure AOSP does not |
| Tablet support | strongly preferred | 2000×1200 landscape, 240 dpi |
| Max size | **≤ ~6.4 GiB** | after deleting `product_a` |

The device also advertises 32-bit support (`abilist32 = armeabi-v7a,armeabi`), so a
*64-bit-only* GSI would silently break any 32-bit app. Prefer arm64 GSIs that keep both.

### The Google-apps decision

Your stock build is a **GMS** build: 210 packages, 85 of them Google, Play Store installed.

- A **vanilla** GSI (`aosp_arm64`, LineageOS `v` variants) has **no Play Store and no Play
  Services**. You would need microG or Aurora Store, and apps depending on Play Services
  (banking, many games, some streaming) will misbehave.
- A **GMS** GSI keeps them, at the cost of size and Google's telemetry.

Only one OEM app exists (`cn.com.techvision.sound`), so there is essentially nothing to lose
on the vendor side either way.

## Sizing: how much room you actually have

| | Value |
|---|---|
| `super` total | 9216 MiB (9 GiB) |
| currently allocated | 4743 MiB |
| **free today** | **4473 MiB** |
| `system_a` (current) | 1663 MiB |
| `product_a` (deletable) | 2186 MiB |
| **free after deleting `product_a`** | **6659 MiB** |

A Google GSI with GMS is typically larger than 1663 MiB — Google's own release page warns that
`_gsi_gms_arm64-*` images "might be bigger than the default dynamic system partition size on
your device". A LineageOS arm64 GSI is distributed as a ~1.3 GB `.img.gz`, which unpacks to
roughly 2.5–3.5 GB.

**Conclusion:** you will almost certainly need to delete `product_a` and resize `system_a`.
That is the documented, standard fix and is safe here (see `04-suitability.md` §"four things
that will go wrong").

## Option A — Google's official GSIs

### A1. AOSP GSI, no Google apps

Per-release build branches on the AOSP CI server:

| Android | Branch |
|---|---|
| 13 | <https://ci.android.com/builds/branches/aosp-android13-gsi/grid> |
| 14 | <https://ci.android.com/builds/branches/aosp-android14-gsi/grid> |
| 15 | <https://ci.android.com/builds/branches/aosp-android15-gsi/grid> |

Artefact: `aosp_arm64-img-<build>.zip`, containing `system.img`.
**No Play Store.**

### A2. GSI with GMS

From <https://developer.android.com/topic/generic-system-image/releases>, behind a licence
click-through. As of this project the page lists, newest first:

| Release | Build | SPL |
|---|---|---|
| Android 17 QPR3 (Beta) | `DP11.261016.003` | 2026-10 |
| Android 17 QPR2 / QPR1 / 17 | — | — |
| Android 16 QPR3 (Beta) / QPR2 / QPR1 / 16 | — | — |
| Android 15 QPR2 / QPR1 / 15 | — | — |
| Android 14 QPR1 / 14 | — | — |
| Android 13 QPR3 | — | — |

Artefact: `gsi_gms_arm64-exp-<build>-<id>-<hash>.zip`. SHA-256 is published next to each
download — verify it.

**Caveat that applies to all of Google's GSIs:** they are validated only on Pixel devices.
Your tablet is not a Pixel, and MTK's HALs are quirky.

## Option B — LineageOS GSI (Andy Yan) — the practical recommendation

<https://sourceforge.net/projects/andyyan-gsi/files/>

Actively maintained (the top-level folders were being updated within the hour when checked;
latest published file `lineage-21.0-20260613-UNOFFICIAL-gsi_arm64_vN.img.gz`, 1.3 GB,
released 2026-06-19). It carries the accumulated Treble compatibility patches that matter on
cheap MediaTek hardware, which is exactly why it is the default choice for this class of
device.

### Decoding the filename

```
{arm|a64|arm64}_{a|b}{v|g}{N|S}-{signed|vndklite|personal}
                |      |  |     |
                |      |  |     signed    = signed with the maintainer's keys
                |      |  |     vndklite  = for VNDKLite devices, or writable /system
                |      |  |     personal  = maintainer's personal mods, reference only
                |      |  N = no superuser
                |      |  S = with PHH Superuser
                |      v = vanilla (no GApps)   g = with regular GApps
                a = A-only   b = A/B-capable
```

**For this tablet that means `arm64_bgN`** (A/B, with GApps, no superuser) or `arm64_bvN` if
you want it de-Googled.

### Which version line

| LineageOS | Android | Folder on SourceForge | Fit here |
|---|---|---|---|
| 20 | 13 | `lineage-20-td`, `lineage-20-light` | Baseline; matches the shipped system version |
| **21** | **14** | `lineage-21-pre-qpr2-light`, `lineage-21-pre-qpr2-td`, `lineage-21-td`, `lineage-21-light` | **Best first target.** Newest widely-reported-working on MTK vendor-31 hardware |
| 22 | 15 | `lineage-22-light` | Reported to boot on comparable MTK devices, with regressions (fingerprint readers, brightness). Worth trying after 21 works |
| 23 / 24 | 16 / 17 | `lineage-pure-userdebug` (most recently updated folder) | Unverified on MT8781. Check the build's `ro.build.version.release` before flashing |

`td` = includes TrebleDroid patches (better compatibility on odd vendors); `light` = the
maintainer's lighter pre-QPR2 line. If a `td` build of 21 is available, prefer it — those
patches exist for devices like this one.

## Option C — others

| Project | Use when |
|---|---|
| **/e/OS GSI** | you want de-Googled with a polished, maintained UI |
| **crDroid / Evolution X / Pixel Experience GSIs** | you want modern UI features and accept more breakage |
| **TrebleDroid (phhusson) AOSP** | you want the closest thing to a reference AOSP GSI with MTK-friendly patches |

One XDA member claims to have run **crDroid** on a T3. Unverified, no logs — but it means at
least one modern GSI has reportedly booted on this hardware.

## Recommendation, in order

1. **LineageOS 21 `arm64_bgN` (or `arm64_bvN`)** — best odds of a usable daily driver on this
   SoC, and keeps Play Store if you want it.
2. **Google `gsi_gms_arm64` Android 14** — if you want an unmodified Google build with a
   current security patch.
3. **LineageOS 22 (Android 15)** — only after 1 or 2 works, and expect regressions.
4. **Anything Android 16/17** — experimental. No evidence for or against on MT8781.

Whatever you pick, **verify before flashing**:

```bash
unzip -o gsi.zip && file system.img          # expect "Linux rev 1.0 ext4 filesystem data"
simg2img system.img /dev/null && echo "sparse, convertible"   # or just convert it
stat -c%s system.img                          # must be < ~6.4 GiB
```

And for the DSU test path, the image must be **unsparsed and gzipped**:

```bash
simg2img system.img system_raw.img
gzip -c system_raw.img > system_raw.gz
```

## A note on what "Android 14 on a vendor-31 device" actually means

Google publishes **no** table of "GSI version → minimum vendor API level". Anyone quoting one
is inferring. What is documented is that the LLNDK is backward compatible and that newer
system images retain legacy VNDK APEXes for older vendors, so a vendor-31 device is *inside*
the supported envelope by design — but feature-level breakage (fingerprint, camera, brightness,
RIL) is common and SoC-specific.

Also: `ro.vendor.api_level` will stay **31** forever. It is frozen at the device's first API
level. A newer GSI does not change it, and anything that reads it (including some Play
Integrity checks) will still see an Android 12 vendor.
