# GSIs — what they are, and why this tablet is a candidate

## 1. Definition

Google defines a **Generic System Image (GSI)** as:

> *a pure Android implementation with unmodified Android Open Source Project (AOSP) code,
> runnable on a variety of Android devices.*
> — <https://developer.android.com/topic/generic-system-image>

The essential idea is that Project Treble split Android into a **system** part (framework,
apps, UI) and a **vendor** part (HALs, kernel modules, firmware blobs, device-specific
configuration). If a device's vendor part is well behaved, you can replace the whole system
part with a build that knows nothing about the hardware — the hardware still works, because
the vendor side is unchanged.

A GSI is therefore **not a port**. It contains no device tree, no kernel, no vendor blobs.
It is one `system.img` that boots on any sufficiently Treble-compliant device.

## 2. Why manufacturers use them (and why this tablet is one)

Writing a full Android port is expensive. Writing a *vendor* BSP is much less so. A large
fraction of budget MediaTek tablets are shipped as:

```
MTK Android BSP (vendor, kernel, HALs)  +  Google GSI-derived system image
```

Our tablet is literally that (see `02-firmware-forensics.md` §2):

```
ro.bootimage.build.fingerprint = Android/gsi_arm64/generic_arm64:12/SGR1.240502.001.B3/...
ro.product.bootimage.name      = gsi_arm64
```

`SGR1` is a Google GSI release branch. So the practical question is not *"can this device
run a GSI"* but *"which GSI build should replace the one it shipped with"*.

That also explains the lack of updates: the OEM is not maintaining an Android fork. They
are tracking a BSP drop. When MTK stops dropping new BSP versions for MT6789, the product
stops getting updates — there is no in-house Android team to backport anything.

## 3. Google's own three-step suitability test

From <https://developer.android.com/topic/generic-system-image>, a device must:

1. have an **unlocked bootloader**,
2. be **fully Treble-compliant**, and
3. have **launched with Android 9 (API 28) or higher**.

The page then gives a concrete test for step 2:

```bash
adb shell getprop ro.treble.enabled
# must be "true"

adb shell cat /system/etc/ld.config.version_identifier.txt | grep -A 20 "\[vendor\]"
# look for: namespace.default.isolated = true

adb shell getprop ro.product.cpu.abi
# choose the GSI matching this: arm64-v8a -> arm64 GSI
```

`namespace.default.isolated = true` is the key one. Google's wording:

> *If the value for that attribute is `true`, then the device fully supports Vendor Native
> Development Kit (VNDK) and can use any GSI operating system version that is newer than the
> on-device OS version. Whenever possible, use the latest GSI OS version that is available.*

**Result for the Lincplus T3:**

```
$ adb shell getprop ro.treble.enabled
true

$ adb shell grep -A 30 '^\[vendor\]' /linkerconfig/ld.config.txt | grep isolated
namespace.default.isolated = true

$ adb shell getprop ro.product.cpu.abi
arm64-v8a
```

All three pass. Note the documentation's suggested path is stale: on Android 13 the file is
`/linkerconfig/ld.config.txt`, and `/linkerconfig` is root-only, which is why the `grep`
form above works where `cat` fails with "Permission denied".

## 4. What GSI releases exist

Google publishes two families, both from the same source tree as the corresponding Pixel
builds:

| Family | Contents | Where |
|---|---|---|
| `aosp_arm64` | Pure AOSP, **no Google apps** | AOSP CI: <https://ci.android.com/builds/branches/aosp-android13-gsi/grid> (one branch per release: `aosp-android10-gsi` … ) |
| `gsi_gms_arm64` | GSI **+ GMS** (Play Store, Play Services) | <https://developer.android.com/topic/generic-system-image/releases> (behind a click-through licence) |

As of this project (late 2026) the release page lists, newest first:

- Android 17 QPR3 (Beta) — `DP11.261016.003`, Oct 2026 SPL
- Android 17 QPR2 (Beta), Android 17 QPR1, Android 17
- Android 16 QPR3 (Beta), QPR2, QPR1, Android 16
- Android 15 QPR2, QPR1, Android 15
- Android 14 QPR1, Android 14
- Android 13 QPR3

Each release is validated by Google only on Pixel devices. Everything else is "should work".

Google also warns explicitly:

> *System partition size: GSI + GMS file size (images named `_gsi_gms_arm64-*`) might be
> bigger than the default dynamic system partition size on your device.*

That matters here — our `system_a` is 1663 MiB, which is too small for a GMS GSI. See
`05-image-options.md`.

### Third-party GSIs

Because a GSI is just a `system.img`, the community builds its own. These are often *better
than* Google's on cheap MediaTek hardware because they carry compatibility patches for
exactly this class of device:

| Project | Notes |
|---|---|
| **LineageOS GSI** (Andy Yan / `AndyCGYan`) | The de-facto standard. `lineage-2x.0-*-gsi_arm64_vN.img`. Actively maintained, tracking current Android. <https://sourceforge.net/projects/andyyan-gsi/files/> |
| **TrebleDroid** (phhusson) | The original AOSP-derived GSI project; source of many Treble fixes. |
| **/e/OS GSI** | De-Googled, privacy-oriented. |
| **crDroid / Evolution X / others** | Feature-rich GSIs from the custom-ROM scene. |

None of these are "official". They are built from AOSP + patches, signed with the
maintainer's own key, and come with no warranty. But they are the realistic daily-driver
option and they are what most people actually run.

## 5. Two ways to install one

### 5.1 Flash it (permanent)

Replace the `system` logical partition inside `super` with the GSI, wipe userdata, reboot.
Requirements: unlocked bootloader, `fastbootd`, and the ability to disable AVB verification.

This is what Google documents:

```bash
fastboot reboot fastboot        # enter fastbootd (userspace fastboot)
fastboot erase system
fastboot flash system system.img
fastboot -w
fastboot --disable-verification flash vbmeta vbmeta.img
fastboot reboot
```

and, when the system partition is too small:

```bash
fastboot delete-logical-partition product_a
```

On our device, `fastboot` in *bootloader* mode cannot touch logical partitions at all
(Virtual A/B); everything above has to happen in `fastbootd`.

### 5.2 Dynamic System Updates (DSU) — non-destructive

Android 10+ can boot a GSI **without flashing it**:

> *DSU … Downloads a new GSI (or other Android system image) onto your device. Creates a new
> dynamic partition. Loads the downloaded GSI onto the new partition. Boots the GSI as a
> guest OS on the device. DSU also enables you to easily switch between the current system
> image and the GSI so you can try GSI without risking corruption of the current system
> image.*
> — <https://developer.android.com/topic/dsu>

The GSI is written into a dynamic partition carved out of `/data`. A cold reboot returns to
the original system, or you discard the install.

Two constraints that matter to us:

1. **DSU requires the image to be signed by a key the device trusts** — Google's or the
   OEM's. This device's `otacerts.zip` contains exactly one certificate, and it is neither:
   it is a **Techvision self-signed cert** (see `02-firmware-forensics.md` §6.1). So
   Google-signed GSIs will not validate, **and neither would anything we sign**, because we
   do not hold Techvision's private key.

   That is the crucial difference from the optimistic version of this plan: on many devices
   the OEM leaves the AOSP test key installed, which lets you sign your own payload. Here
   they did not. There is no key we possess that this device trusts, for AVB, OTA or DSU.

   Workarounds exist but are all weaker than they look: `VegaBobo/DSU-Sideloader` is only a
   helper UI and still goes through the same `gsid` verification; `--ignore-signature` is a
   flag on some *other* tools, not on `gsid`; patching `gsid` needs root, which is the thing
   we are trying to avoid.

   **Practical conclusion: DSU is probably blocked on this tablet.** It is still worth one
   cheap attempt — `gsi_tool status` says `normal` and a failure is harmless — but do not
   plan the project around it.
2. DSU is a *manufacturer-provided feature*. It is present on this device — `com.android.dynsystem`
   is installed, `/system/etc/init/gsid.rc` exists, `gsi_tool status` returns `normal` — but
   "present" is not the same as "functional".

The value of DSU, if it works, is enormous: it is the only way to answer *"does a modern GSI
boot on this tablet"* without touching the bootloader or any flash partition. Because the
signature gate is likely closed, the realistic minimum-risk test is instead the **SP Flash
Tool path** (`07-procedure.md` Phase 7): build a `super.img` containing the GSI, flash it in
`Download Only` mode, and keep the stock `super.img` ready to put back. That is more work but
it does not require an unlock and does not touch `seccfg`, so the TEE — and therefore
Widevine L1 — is never exposed to an `orange` boot state.

## 6. What a GSI does and does not give you

**Kept, because it lives in `/vendor`, `/vendor_dlkm`, `/odm_dlkm`, `vendor_boot`:**

- kernel and kernel modules
- all hardware HALs (display composer, audio, camera, sensors, Wi-Fi/BT, GNSS)
- firmware blobs and the Trustonic TEE integration
- Widevine HAL + `liboemcrypto.so`
- the device's own audio tuning, camera IQ tuning, display calibration

**Replaced, because it lives in `/system`:**

- the entire framework, SystemUI, Settings, launcher
- Google apps (unless the GSI is GMS-flavoured — a pure AOSP GSI has **no Play Store**)
- OEM preinstalled apps
- the OEM's `product` partition apps (if `product` is deleted to make room)

**Genuinely lost or degraded — the honest list:**

- Verified boot goes from `green` to `orange` (unlocked bootloader). Permanent until you
  re-lock, and re-locking with non-stock images bricks the device.
- Play Integrity `DEVICE`/`STRONG` verdicts. Banking apps, Google Wallet, some games stop
  working. `BASIC` may survive with effort.
- OEM-specific UI features (split-screen handwriting, stylus shortcuts, kids mode, OEM
  camera app features).
- Whatever the OEM customised that is not in `/vendor` — e.g. their `product` overlays,
  their display cutout/rounded-corner config, their navigation-bar mode.
- Wi-Fi Display / Miracast if it was implemented in `/system`.
- Official OTA updates. The `update_engine` payloads will no longer apply (the system
  partition hash changed), so you are frozen at the GSI you install, and must update by
  re-flashing.

For the specific question of **Widevine / Netflix**, see `06-backup-and-risk.md` — the
answer is more nuanced than the internet's "you always lose L1", because on this device the
DRM implementation is entirely on the vendor side.

## 7. GSI vs "a custom ROM"

Worth stating plainly, because the two get conflated:

| | Custom ROM (device-specific) | GSI |
|---|---|---|
| Needs a device tree | Yes | No |
| Touches kernel/vendor | Usually | Never |
| Device-specific fixes | Built in | Applied at runtime (overlays, props) |
| Effort to make | Months, per device | Zero — it already exists |
| Hardware support | Best possible | "Whatever the vendor HAL allows" |
| Maintained per device | No | Yes, upstream |

For a tablet nobody has ever ported, a GSI is the *only* realistic path to a modern Android.
A true custom ROM is not possible here: it would require Lincplus/Techvision to release the
kernel source and the vendor tree, and there is no evidence they have.
