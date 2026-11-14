# Suitability assessment — verdict

## Verdict

**This tablet is an excellent GSI candidate — close to a best case, for three independent
reasons.**

1. **It is already running a GSI.** The shipped `boot.img` is Google's own
   `gsi_arm64/generic_arm64` image (`SGR1.240502.001.B3`, Android 12 branch). The OEM did not
   write an Android; they layered a GSI-shaped system on an MTK Android 12 BSP. Replacing it
   with a newer GSI is maintenance, not surgery.
2. **Every mechanical requirement is satisfied and was verified live on the device**, not
   inferred from marketing or from a similar device. Treble ✅, full VNDK isolation ✅,
   arm64 ✅, dynamic `super` ✅, Virtual A/B ✅, bootloader `fastboot` ✅, `fastbootd` ✅,
   `unlock_ability: true` ✅.
3. **There is a total-recovery path.** Lincplus publishes a complete SP Flash Tool firmware
   package. A bad `system` flash cannot brick the device — the preloader runs before any
   Android partition is consulted, and the flash tool talks to that layer, not to Android.
   (Note the door on this SoC is *preloader* mode with a signed Download Agent, not BROM —
   MT6789 is a patched-bootrom "V6" part. Same conclusion, different entry point.) Even a
   soft-brick is a 10-minute reflash.

It is also a *simple* candidate: it is Wi-Fi-only with no modem, no telephony, no SIM. That
eliminates the single most common cause of failed Mediatek GSI installs (RIL/IMS crashes and
the modem partition chicken-and-egg).

## Requirement-by-requirement

| Requirement | Evidence | Verdict |
|---|---|---|
| Bootloader unlockable | `fastboot flashing get_unlock_ability` → `unlock_ability is true` | ✅ |
| Bootloader reachable | `adb reboot bootloader` → `fastboot devices` → `SERIAL-DAILY fastboot` | ✅ |
| `fastbootd` reachable | `fastboot reboot fastboot` → `fastboot devices` → `SERIAL-DAILY fastbootd`, `is-userspace: yes` | ✅ |
| Treble | `ro.treble.enabled=true` | ✅ |
| Full VNDK (can run *newer* GSI) | `namespace.default.isolated = true` in `[vendor]` of `/linkerconfig/ld.config.txt` | ✅ |
| Architecture | `ro.product.cpu.abi=arm64-v8a` → `arm64` GSI | ✅ |
| Launched Android 9+ | `ro.product.first_api_level=33`, `ro.board.first_api_level=31` | ✅ |
| Dynamic partitions | `super` 9 GiB, liblp metadata v10.2, `header flags: virtual_ab_device` | ✅ |
| Logical partitions visible to fastbootd | `is-logical:system_a: yes`, `partition-size:system_a: 0x67F2A000` | ✅ |
| Enough room for a GSI | 4473 MiB free in `super`; 6659 MiB free if `product_a` deleted | ✅ |
| No in-flight snapshot (VAB safety) | `snapshot-update-status: none` | ✅ |
| Recovery if it goes wrong | OEM SP Flash Tool v6 package + full `super.img` | ✅ |
| No modem/telephony complications | Wi-Fi-only SKU, no `md1img`, `mtk_ps1_rat=no` | ✅ |
| Tablet form factor | `ro.build.characteristics=tablet` | ✅ |

## The four things that will actually go wrong (and are all fixable)

These are the realistic friction points, in order of likelihood.

### 1. `system_a` is too small (certain)

`partition-size:system_a` is **1663 MiB**. A pure-AOSP arm64 GSI is roughly 1.5–2 GiB
(compressed/unsparse depending on build) and a **GMS** GSI is larger still — Google's own
release notes warn about exactly this (*"GSI + GMS file size … might be bigger than the
default dynamic system partition size on your device"*).

Fix, in `fastbootd`:

```bash
fastboot delete-logical-partition product_a     # frees 2186 MiB
fastboot resize-logical-partition system_a 0    # 0 = use all remaining group space
```

`super` is 9 GiB with only 4.6 GiB used, so after deleting `product` there is ~6.5 GiB of
contiguous room. This is safe *because* `/vendor` is untouched — the GSI brings its own
`system_ext` inside `system.img`, and this device never had a real `system_ext` partition
anyway (`/system_ext` is just a symlink into `/system`).

### 2. AVB will refuse to boot the modified system (certain)

`vbmeta_system` carries the hashtree root for `system` and `product`. Flashing a GSI changes
that root. With `ro.boot.veritymode=enforcing` and a locked bootloader, the device will not
boot.

Fix: unlock, then disable verification for the whole chain from the top-level `vbmeta`:

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
```

Because `vbmeta` chains `boot`, `vbmeta_system` and `vbmeta_vendor`, setting the wrong
flag at the root is enough — but **only if the bootloader accepts the vbmeta image you
flash.** We do not hold the OEM's AVB private key (see `02-firmware-forensics.md` §6.1), so
the safest sequence is to patch the *flags field* of the **existing** OEM `vbmeta.img`
rather than substituting Google's 512-byte one, and to verify the result with
`avbtool info_image`. See `07-procedure.md` §4 for the exact command.

### 3. Density / orientation will be wrong on first boot (very likely)

The panel is 2000×1200 at 240 dpi with `primary_display_orientation=ORIENTATION_270`, i.e.
a landscape tablet with a rotated panel. A GSI defaults to phone-ish behaviour and often
comes up at the wrong density, sideways, or with a nav bar across the bottom in landscape.

Fix: a GSI `*-tablet` variant if available, otherwise at runtime:

```bash
adb shell wm size 2000x1200
adb shell wm density 240
adb shell cmd overlay enable-exclusive com.android.internal.systemui.navbar.gestural
```

Google documents the nav-bar overlay command explicitly for GSI
(`fastboot`/`adb exec-out cmd overlay enable-exclusive …`). Orientation is the harder one —
it may need `ro.surface_flinger.primary_display_orientation` in a runtime prop override.

### 4. Play Integrity / DRM — degraded but probably not destroyed

`verifiedbootstate` goes `green` → `orange` the moment you unlock, and that alone breaks
banking apps and Wallet regardless of what you flash. Widevine is a separate question and
looks *better* than usual on this device because the whole DRM stack (HAL 1.4, `liboemcrypto`,
Trustonic TEE integration) lives in `/vendor`, which a system-only GSI never touches.
Full analysis in `06-backup-and-risk.md`.

## What this device is *not* good for

- **No cellular, ever.** There is no modem. Any GSI is Wi-Fi-only, which is fine for a tablet
  but means no LTE SKU of this hardware can reuse this procedure 1:1 (it would need the
  modem partitions and IMEI handling).
- **No gyroscope, magnetometer or compass.** A GSI cannot invent them.
- **Composer HAL 2.1** is the oldest component in the stack. Expect animation smoothness to
  be slightly worse than a modern device; no GSI can fix that without a vendor update.
- **32-bit app support is present** (`armeabi-v7a` in `abilist32`), so a 64-bit-only GSI
  would break any old 32-bit apps. Prefer `arm64` GSIs that keep `arm64-v8a,armeabi-v7a`.

## Confidence

| Claim | Confidence | Basis |
|---|---|---|
| A modern arm64 GSI will boot | **High** | device already runs one; all mechanical gates verified live |
| Full recovery from a bad flash | **High** | OEM SP Flash Tool package + signed DA present; preloader-level flashing is independent of Android |
| Widevine survives / stays L1 | **Medium** | vendor-side DRM untouched, but unproven on this device |
| Play Integrity `DEVICE` survives | **Low** | needs spoofing workarounds; likely no |
| Everything (camera, sensors, audio) works first try | **Medium** | all HALs are HIDL 1.x and vendor-side; most should work |

The honest summary: **the install will almost certainly work; the polish will need a few
iterations.**
