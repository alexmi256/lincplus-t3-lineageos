# Keeping Widevine L1 on an Android 14 GSI

**Result: Widevine L1, HDCP 2.3, 50 sessions, System ID 29739 — on LineageOS 21 (Android 14) —
by giving the GSI the tablet's certified build identity.**

Measured on Lincplus T3 (MT8781 / `tb8781p1_64_wifi`), bootloader unlocked, `verifiedbootstate orange`.

## The problem

A GSI on this tablet reports **L3** instead of **L1**:

| Field | Stock | GSI as shipped | GSI + stock identity |
|---|---|---|---|
| Security level | L1 | L3 | **L1** |
| System ID | `29739` | `28917` | **`29739`** |
| Max HDCP | HDCP 2.3 | None | **HDCP 2.3** |
| Current HDCP | No Digital Output | None | **No Digital Output** |
| Max sessions | 50 | 16 | **50** |
| CDM version | `16.1.1@006` | `16.1.1@006` | `16.1.1@006` |

The CDM **version never changes** — it is the same library in all three cases.

## Why it happens

**The CDM is not in the GSI.** Scanning the images for Widevine symbols:

| Image | `libwvhidl` | `libwvdrmengine` | `liboemcrypto` |
|---|---|---|---|
| OEM `vendor_a` | 5 | 63 | 12 |
| LineageOS 21 GSI `system` | 0 | 0 | 0 |
| Google AOSP 14 GSI `system` | 0 | 0 | 0 |

So there is nothing to "swap" — the same vendor CDM runs in every case. What differs is
**provisioning**. A provisioned device reports its certified identity (`29739`, 50 sessions, HDCP
2.3); when provisioning is refused the CDM falls back to a provisional software identity
(`28917`, 16 sessions, no HDCP).

Provisioning is gated on the **build identity the system presents**. A GSI presents
`google/lineage_arm64_bgN/tdgsi_arm64_ab:14/...`, which is not a certified device, so the request
is refused and the CDM degrades itself.

Unlocking the bootloader is **not** a factor — stock, unlocked measured L1 (see
`baseline-SERIAL-TEST.md`).

## The fix

Rewrite the identity properties inside the GSI's `system.img` so the composed fingerprint is the
certified one.

**Which props matter.** `init` resolves `ro.product.*` from the first source listed in
`ro.product.property_source_order` that defines it. On a GSI that is the **product overlay baked
into `system.img`** (`/system/product/etc/build.prop`), not the OEM product partition — patching
only `ro.product.system.*` leaves the fingerprint reading `google/...`. Three files must be patched:

| File | Props |
|---|---|
| `/system/build.prop` | `ro.product.system.*`, `ro.build.id`, `ro.build.version.incremental`, `ro.system.build.fingerprint` |
| `/system/product/etc/build.prop` | `ro.product.product.*`, `ro.product.build.fingerprint` |
| `/system/system_ext/etc/build.prop` | `ro.product.system_ext.*`, `ro.system_ext.build.fingerprint` |

Set `brand=Lincplus`, `device=name=model=T3_US`, `ro.build.id=TP1A.220624.014`,
`ro.build.version.incremental=20241016`.

**`ro.build.version.release` and `ro.build.type` do NOT need to match stock.** The verified run
still reported `:14` and `userdebug` and provisioned L1 anyway:

```
Lincplus/T3_US/T3_US:14/TP1A.220624.014/20241016:userdebug/release-keys
```

That matters practically: keeping `userdebug` keeps `adb root` working, which is what lets you run
the PairIP-wrapped DRM app at all (see F36).

**Why `debugfs` and not a mount.** Android system images are ext4 with the `shared_blocks` feature
and are usually 100% full. `mount -o rw` fails, and `e2fsck -E unshare_blocks` cannot duplicate
extents when there is no free space. `debugfs` can replace a file in place:

```bash
debugfs -R "dump /system/product/etc/build.prop" system.img > /tmp/p
# edit /tmp/p
debugfs -w -R "rm /system/product/etc/build.prop" system.img
debugfs -w -R "write /tmp/p.new /system/product/etc/build.prop" system.img
```

Scripted in `build/patch-gsi-identity.sh <system.img> [brand] [device] [build_id] [incremental]`.

## Full procedure

```bash
# 1. patch identity into the GSI's system image
docker run --rm -v /flashcache/hermes/projects/Lincplu.T3.Update:/work debian:bookworm \
  bash /work/build/patch-gsi-identity.sh /work/build/lineage-stockid.img

# 2. assemble super (system_a = patched GSI, rest = OEM stock)
docker run --rm -v /flashcache/hermes/projects/Lincplu.T3.Update:/work \
  lincplus-android-tools:5 bash /work/build/make-super-stockid.sh

# 3. flash
fastboot flash vbmeta vbmeta-flags3.img     # flags 3: system_a is not vendor-signed
fastboot reboot fastboot
fastboot flash super super-stockid.img
fastboot reboot
```

No userdata wipe is required when only props change (the PairIP component-disable state survives,
so the DRM app still runs).

## Verifying

```bash
adb shell getprop ro.build.fingerprint
# Lincplus/T3_US/T3_US:14/TP1A.220624.014/20241016:userdebug/release-keys

adb shell getprop ro.product.brand     # Lincplus
adb shell getprop ro.product.device    # T3_US
```

Then DRM Info must show **L1, SysID 29739, HDCP 2.3, 50 sessions**. If it shows L3 / 28917 / 16,
the identity did not fully take — check `ro.product.product.brand` first, since the product overlay
outranks everything else.

## Caveat

This restores Widevine L1, not full device certification. Play Protect certification / SafetyNet
grade the *build* separately and will still see a GSI, so banking apps and Play's "device is
certified" check may still complain. Widevine-protected HD playback, which is what L1 governs,
works.

## Confirmed again on Android 15 (LineageOS 22.2), and a sharper reading of the mechanism

Measured 2026-11-14 on the same unit, running a **self-built** 22.2 image
(`lineage_gsi_arm64_gN-userdebug 15 BP1A.250505.005`, SPL 2026-11-01):

| Reading | Value |
|---|---|
| Security Level | **L1** |
| System ID | **29739** |
| Max HDCP | **2.3** |
| Max sessions | **50** |
| CDM | 16.1.1@006 |
| OEM Crypto API | 16 |

So the fix is not an Android 14 artefact — it carries to Android 15 unchanged.

**Two refinements to the mechanism described above:**

1. **`ro.build.tags=test-keys` does not block L1.** This build is unsigned, and provisioning still
   succeeded. Signing matters for Play Integrity and for looking like a retail device; it is not a
   precondition for Widevine L1 on this hardware.
2. **The literal fingerprint string is not what the CDM reads.** After patching, the device reports
   `ro.product.brand=Lincplus`, `ro.product.device=T3_US`, `ro.product.model=T3_US`, while
   `ro.build.fingerprint` is *still* the generic `generic/lineage_gsi_arm64_gN/...` string. L1 was
   granted anyway. The gate is the resolved device identity props plus build id/incremental — not the
   fingerprint literal. This is consistent with the Android 14 result, where patching only
   `ro.product.system.*` failed because the product overlay outranked it.

Practical consequence: the three-file patch remains the minimum needed, but there is no reason to care
about rewriting `ro.build.fingerprint` itself.

## Prior art, and how this differs

Surveyed while writing this up (browser-fetched, not scraped summaries):

**1. The dominant public explanation is wrong on two counts.** Search engines' AI overviews, Reddit
threads and vendor forums state that unlocking the bootloader "blocks TEE access" and that a GSI
"lacks the OEM DRM blobs". Measured here: stock **unlocked** still reads L1, and both GSIs contain
**zero** Widevine symbols while the vendor CDM runs fine. The cause is provisioning, not keys and
not missing libraries.

**2. The specific claim that spoofing cannot work is half right.** Google's AI overview asserts
that *"spoofing `ro.product.system.*` or the build fingerprint alone cannot restore Widevine L1 on
a GSI"* — which matches our own failed first attempt. It is wrong about the achievable outcome:
patching **all three** identity overlays (`system`, `product`, `system_ext`) did restore L1. Anyone
following the common advice of setting `ro.product.system.*` will conclude it is impossible,
because the product overlay silently outranks it.

**3. Established device-specific method: TEE keybox reprovisioning.** The mature work in this area
targets Qualcomm devices where unlocking genuinely destroys keybox access, and works by
*reprovisioning the TEE* (`KmInstallKeybox`) and restoring removed binaries, requiring
Magisk/KernelSU:

- `github.com/Ubuntuify/nothing-widevine` — Nothing Phone (3a), "reprovisioning the TEE and adding
  removed binaries on Custom ROMs"; success verified by a **5-digit system ID**, the same signal
  used here.
- `xdaforums.com/t/fix-widevine-l1-unlocked-bootloader.4731374/` — the underlying thread, covering
  Nothing / OPPO / OnePlus / Realme Qualcomm platforms.
- `github.com/wh1ter0z3/Reprogram-TEE-on-Qualcomm-devices` — the reprovisioning guide.

**4. What is different here.** This is a MediaTek MT8781 device, and **no keybox or TEE
reprovisioning was needed** — the keybox was intact and provisioned correctly on stock, unlocked.
Only the *build identity* was wrong. The fix is therefore a static image edit, applied before
flashing, needing no root on the device at all (root was used here only to run a PairIP-wrapped
measurement app). Stated as a mechanism rather than a device quirk:

> On this vendor stack, Widevine L1 provisioning is gated on the *build identity* the system
> presents, not on bootloader lock state and not on keybox availability. Presenting an uncertified
> identity causes the CDM to fall back to provisional L3; presenting the certified one restores
> the original L1 identity (SysID `29739`, HDCP 2.3, 50 sessions) with no change to `/vendor`.

**5. Corollary worth stating explicitly:** "unlocking kills Widevine L1" is **vendor policy, not an
Android rule**. It holds on several Qualcomm OEMs (OnePlus/OPPO/Nothing/Realme per the threads
above) and does not hold on this MediaTek unit. Any guide that generalises it is overreaching, and
anyone deciding whether to unlock should measure rather than assume.

**6. Not claimed:** this does not repair Play Integrity / SafetyNet certification, and it should
not be expected to work on devices whose keybox is genuinely revoked on unlock — those need the
TEE reprovisioning route in (3). Untested here.

## Open question

The spoofed fingerprint differs from stock in release (`14` vs `13`) and type (`userdebug` vs
`user`) yet still provisioned L1, so the gate appears to be brand/device/name/model plus build
id/incremental — not the release/type pair. Narrowing that would mean bisecting the props. Worth
doing only if it matters: keeping `userdebug` is what preserves `adb root`.

