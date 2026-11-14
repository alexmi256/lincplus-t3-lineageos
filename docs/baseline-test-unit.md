# Stock baseline — unit SERIAL-TEST

Captured **before** any modification, via the DRM Info app on the device itself
(screenshot: `build/drm-baseline.png`). This is the reference every later measurement is
compared against.

## Device

| Field | Value |
|---|---|
| Model / brand | Lincplus **T3_US** |
| Hardware / SoC | `mt8781`, MediaTek **MT8781V/NA** |
| Build | `TP1A.220624.014.20241016 release-keys` |
| Build fingerprint | `Lincplus/T3_US/T3_US:13/TP1A.220624.014/20241016:user/release-keys` |
| Build type | user (release-keys) |
| Android | 13, SDK 33 |
| ABIs | `arm64-v8a`, `armeabi-v7a`, `armeabi` — **32-bit support present** |
| Spatial audio / head tracking | not supported |

## Widevine (the thing to protect)

| Field | Value |
|---|---|
| **Security Level** | **L1** |
| Vendor | Google |
| Version | `16.1.1@006` |
| System ID | `29739` |
| Max HDCP level | HDCP 2.3 |
| Current HDCP level | No Digital Output |
| Max sessions | 50 |
| OEM Crypto API version | 16 |

## Bootloader

| Field | Value |
|---|---|
| `ro.boot.verifiedbootstate` | `green` |
| `ro.boot.flash.locked` | `1` |
| `sys.oem_unlock_allowed` | `1` (OEM unlocking enabled in developer options) |
| `ro.boot.slot_suffix` | `_a` |
| Battery at capture | 63% |
| `ro.vendor.api_level` | 31 (Android 12 vendor — stays 31 forever) |

## What this establishes

- **L1 is real and hardware-backed here**, with HDCP 2.3 available. Netflix/Prime HD is currently
  possible, so any later regression is measurable rather than theoretical.
- The 32-bit ABIs (`armeabi-v7a`, `armeabi`) are present, so a 64-bit-only GSI would silently
  break 32-bit apps. The chosen GSI is `arm64_bgN`, which keeps both.
- The build is `20241016` — the same build as the OEM firmware package
  (`TVE1070M_US_MT8781_A13_WIFI_user_20241016.212541`), so the vendor partitions in the
  assembled `super.img` are the correct ones for this unit.

## Measured results

| Field | **A: stock, locked** | **B: stock, unlocked** | **C: GSI (LineageOS 21)** | **D: GSI + stock identity** |
|---|---|---|---|---|
| **Security Level** | **L1** | **L1** ✅ | **L3** ✗ | **L1** ✅ |
| System ID | `29739` | `29739` | `28917` | `29739` |
| Max HDCP | HDCP 2.3 | HDCP 2.3 | None | **HDCP 2.3** |
| Max sessions | 50 | 50 | 16 | 50 |
| CDM version | `16.1.1@006` | `16.1.1@006` | `16.1.1@006` | `16.1.1@006` |
| `verifiedbootstate` | `green` | `orange` | `orange` | `orange` |

Phase D is **Android 14 with Widevine L1 restored** by patching the GSI's build identity to the
certified one — full recipe in `10-widevine-l1-on-gsi.md`. The fingerprint it presented was
`Lincplus/T3_US/T3_US:14/TP1A.220624.014/20241016:userdebug/release-keys`: stock brand/device and
build id, but still release 14 and `userdebug`, and that was enough.

## Conclusion: the unlock is free, the GSI costs L1

Phase B is byte-identical to Phase A on every DRM field — security level, System ID, HDCP and
session count all unchanged — with the bootloader **unlocked** and `verifiedbootstate` orange.
Unlocking therefore does **not** cost Widevine L1 on this device.

Phase C changes all four values at once (L1→L3, SysID `29739`→`28917`, HDCP 2.3→None, sessions
50→16) while the CDM version stays `16.1.1@006`.

**What it is not:** the GSI does not ship its own Widevine. A byte scan of both GSI `system`
images finds no `libwvhidl`, `libwvdrmengine` or `liboemcrypto` at all — every one of those is
present only in the OEM `vendor` partition:

| Partition | `libwvhidl` | `libwvdrmengine` | `liboemcrypto` |
|---|---|---|---|
| `vendor_a` (OEM) | 5 | 63 | 12 |
| AOSP 14 GSI system | 0 | 0 | 0 |
| LineageOS 21 GSI system | 0 | 0 | 0 |

**What it is:** the *same* vendor CDM running unprovisioned. A provisioned L1 CDM reports the
device's certified identity (`29739`, 50 sessions, HDCP 2.3); the provisional software fallback
reports a generated identity (`28917`, 16 sessions, no HDCP). The fingerprint the GSI presents
(`google/lineage_arm64_bgN/...` or `Android/aosp_arm64/generic_arm64/...`) is a generic,
uncertified build string, so hardware provisioning is refused and the CDM degrades itself.

That predicts **any** GSI lands on L3 regardless of which one it is — Google's own AOSP GSI
included — and it points at the build fingerprint / certification as the thing to spoof, rather
than at "LineageOS breaking Widevine". Confirming it means running a GSI with the stock
`ro.product.system.*` values, which needs root on the GSI.

The practical consequence for the writeup: **GSI = Android 14, but Netflix/Prime HD is capped at
L3.** The leverage point is the build identity the GSI presents (which decides whether the vendor
CDM provisions), not the bootloader, not `vbmeta`, and not any Widevine library inside the GSI.

## How Phase B was measured (repeatable)

Stock Android 13 is a `user` build: `pm disable` of the PairIP licence activity fails with
`SecurityException`, and `adb root` is refused. The OEM firmware package ships `boot-debug.img`,
whose ramdisk contains `force_debuggable` + `adb_debug.prop` setting `ro.debuggable=1` and
`ro.adb.secure=0`. Flashing **that** to `boot` (with an unlocked bootloader, as its own comment
requires) yields root on fully stock system software:

```bash
fastboot flash boot boot-debug.img          # from the OEM package's images/
adb root && adb shell id                    # uid=0(root)
adb shell pm disable com.androidfung.drminfo/com.pairip.licensecheck.LicenseActivity
adb shell am start -n com.androidfung.drminfo/.MobileActivity
```

No Magisk needed — and no GSI needed, which is what makes the measurement attributable to the
unlock alone.
