# Firmware Forensics — what the Lincplus T3 actually is

Everything in this document was read directly off the device (via `adb`) or parsed out of
the manufacturer firmware package in `FW/TVE1070M_US_MT8781_A13_WIFI_user_20241016.212541/`.
Nothing here is inferred from marketing copy.

---

## 1. Identity

| Property | Value | Source |
|---|---|---|
| Brand | `Lincplus` | `ro.product.brand` |
| Manufacturer / ODM | `Techvision` | `ro.product.manufacturer` |
| Model / device / product | `T3_US` | `ro.product.model` |
| Serial (this unit) | `SERIAL-DAILY` | `ro.boot.serialno` |
| Build fingerprint | `Lincplus/T3_US/T3_US:13/TP1A.220624.014/20241016:user/release-keys` | `ro.build.fingerprint` |
| Android | 13 (SDK 33), build `TP1A.220624.014`, incremental `20241016` | `ro.build.version.*` |
| Security patch | `2024-09-05` | `ro.build.version.security_patch` |
| Build date | 2024-10-16 21:25 CST | `ro.build.date` |
| Build host/user | `test31`, user `test31` | `ro.build.host` / `ro.build.user` |
| Base OS | `...:13/TP1A.220624.014/20240507` (an earlier 2024-05-07 build) | `ro.build.version.base_os` |
| Firmware package | `TVE1070M_US_MT8781_A13_WIFI_user_20241016.212541` | directory name |
| Platform / project | `MT6789` / `tb8781p1_64_wifi` | scatter file `general.project` |
| SoC | MediaTek `MT8781V/NA` (Helio G99 class) | `ro.soc.model`, `ro.hardware` |
| Vendor BSP string | `alps-mp-s0.mp1.rc-V15.175_techvision.s0mp1rc.tb8786p1.64_P3` | `ro.vendor.mediatek.version.release` |

Notes:
- The scatter file is named `MT6789_Android_scatter.txt` and declares `platform: MT6789`,
  while the running SoC reports `MT8781V/NA`. MT6789 and MT8781 are the same die in
  different SKUs; the BSP is built for the MT6789 family and the project is `tb8781p1`.
- The BSP string mentions `tb8786p1` even though the project directory says `tb8781p1`.
  This is normal MTK BSP sloppiness — the vendor re-used a neighbouring project tree.
- `ro.build.user`/`ro.build.host` = `test31` is an unbranded MTK engineering build host.

## 2. The single most important fact

**The system on this tablet is not a vendor-built Android 13. It is a Google generic
system image, dressed up.**

```
ro.bootimage.build.fingerprint = Android/gsi_arm64/generic_arm64:12/SGR1.240502.001.B3/12100364:user/release-keys
ro.product.bootimage.name      = gsi_arm64
ro.product.bootimage.model     = GSI on ARM64
ro.product.bootimage.brand    = Android
ro.product.bootimage.device    = generic_arm64
```

`SGR1` is a Google **GSI release branch**. The `boot.img` shipped by Lincplus is literally
Google's own `gsi_arm64` boot image, dated 2024-05 (`SGR1.240502.001.B3`), re-used as the
generic ramdisk for their GKI device.

This tells us three things:

1. Techvision/Lincplus never built a bespoke Android from scratch. They took an MTK
   Android 12 BSP, and put an Android 13 system image on top.
2. The boot chain is already laid out the way a GSI expects.
3. A GSI is not an exotic hack for this device — it is *how the device was built in the
   first place*. We are replacing one generic system image with a newer one.

## 3. Split between Android versions

| Layer | Version | API level | Fingerprint / evidence |
|---|---|---|---|
| `system` (+`product`, `system_ext`) | Android **13** | 33 | `ro.system.build.version.release=13` |
| `vendor` + `vendor_dlkm` + `odm_dlkm` | Android **12** | 31 | `ro.vendor.build.version.release=12`, `ro.vendor.api_level=31` |
| kernel | `5.10.209-android12` | — | `uname -r` |
| VNDK version | `31` | | `ro.vndk.version=31` |

So the vendor is an Android 12 (S) BSP and the system is a 13 (T) GSI. The device
therefore claims `ro.product.first_api_level=33` while its vendor sits at 31.

This "newer system, older vendor" arrangement is exactly the configuration Google's GSI
program is designed to support.

## 4. Treble / VNDK compliance — passes the official test

Google's documented GSI suitability test (see `03-gsi-explainer.md`) has three steps.
All three pass:

```
$ adb shell getprop ro.treble.enabled
true

$ adb shell grep -A30 '^\[vendor\]' /linkerconfig/ld.config.txt | grep isolated
namespace.default.isolated = true

$ adb shell getprop ro.product.cpu.abi
arm64-v8a
```

`namespace.default.isolated = true` is the important one: it means the vendor namespace is
**fully VNDK-isolated**, which per Google's documentation means the device
*"can use any GSI operating system version that is newer than the on-device OS version."*

Note the file has moved: older guides look in `/system/etc/ld.config.version_identifier.txt`;
on Android 13 it is `/linkerconfig/ld.config.txt` and `/linkerconfig` is root-only, so the
`adb shell grep` form above (no `cat`) is what works.

## 5. Partition layout

### 5.1 Physical (GPT) — from the scatter file, `block_size: 0x20000`

Storage is **UFS 2.2**, 128 GB nominal (`/data` reports 109 GiB usable).

> ⚠️ **Correction from an earlier draft of this document.** The scatter file's *first*
> section says `storage_type: EMMC`, and `ro.vendor.mtk_emmc_support=1` is set, so it is easy
> to conclude "eMMC". Both are misleading. MTK scatter files ship **both** an EMMC and a UFS
> layout in the same file and the flasher picks one at runtime, and `mtk_emmc_support` is a
> BSP-wide capability flag. The device is UFS, on this evidence:
>
> - `ro.boot.boot_devices = bootdevice,soc/11270000.ufshci,11270000.ufshci` — a UFS host
>   controller is the boot device
> - `/sys/bus/platform/devices/11270000.ufshci/` exists and exposes `device_descriptor`,
>   `geometry_descriptor`, `health_descriptor` — UFS-specific SCSI attributes
>   (`11240000.mmc` is the separate SD-card controller)
> - block devices are `sda`/`sdb`/`sdc` (SCSI/UFS naming), not `mmcblk0`
> - UL's PCMark benchmark measured 896 MB/s sequential read, 233 MB/s write — UFS class,
>   far beyond eMMC
>
> (`mmcblk0boot0`/`mmcblk0boot1` do exist without an `mmcblk0`, presumably exposed by the SD
> controller driver; unexplained, but not the system disk.)

The full table is reproduced in `appendix-a-partition-map.md`. The parts that matter:

| Partition | Size | Notes |
|---|---|---|
| `preloader` / `preloader_backup` | 1 MiB each | boot partitions (UFS LU0/LU1; `EMMC_BOOT1/2` in the scatter) |
| `vbmeta` | 8 MiB (8 KiB used) | top-level AVB, chains to `boot`, `vbmeta_system`, `vbmeta_vendor` |
| `vbmeta_system` | 8 MiB (4 KiB used) | signs `system` + `product` |
| `vbmeta_vendor` | 8 MiB (4 KiB used) | signs `vendor` |
| `boot` | 64 MiB | header v4, **contains a ramdisk** (Google gsi_arm64 generic ramdisk) |
| `vendor_boot` | 64 MiB | header v4, 22.4 MB vendor ramdisk + 186 KB dtb + ramdisk table |
| `init_boot` | 8 MiB | **partition exists in GPT but is unused** (scatter: `file_name: NONE`) |
| `dtbo` | 8 MiB (38 KB used) | |
| `super` | **9 GiB** (`0x240000000`) | dynamic partition container |
| `userdata` | 3 GiB declared, `NEEDRESIZE` | resized to fill the storage device at first boot |
| `metadata` | 32 MiB | encryption key directory (`/metadata/vold/metadata_encryption`) |
| `persist` | ~54 MiB | sensor/Wi-Fi/BT calibration — **per-unit, not in the firmware package** |
| `nvdata`, `nvcfg`, `nvram`, `proinfo`, `protect1/2`, `otp`, `seccfg`, `expdb`, `frp` | various | per-unit MTK data — see `06-backup-and-risk.md` |

### 5.2 Dynamic partitions inside `super`

Parsed with `work/tools/lpdump.py` (a dependency-free liblp metadata parser written for
this project, because `lpdump` is not packaged on Debian):

```
metadata v10.2, header_size=256, flags=0x1
block device: super, first_sector=2048, size=9663676416 (9 GiB)
groups: default (unlimited), main_a (9 GiB), main_b (9 GiB)

PARTITION        GROUP   SECTORS     SIZE
odm_dlkm_a       main_a       680    0.3 MiB
product_a        main_a   4476752 2185.9 MiB
system_a         main_a   3406160 1663.2 MiB
system_b         main_b    235592  115.0 MiB      <- system_other for slot B
vendor_a         main_a   1532608  748.3 MiB
vendor_dlkm_a    main_a     62024   30.3 MiB
```

Total allocated **4743 MiB of 9216 MiB** → **4473 MiB (4.37 GiB) free** inside `super`
right now, and **6659 MiB free if `product_a` is deleted**.

`system_b` at 115 MiB is not a second system — it is the `system_other.img` payload
(120,156,284 bytes) that A/B devices keep for post-OTA dexopt.

**There is no `system_ext` partition.** `/system_ext` is a symlink to `/system/system_ext`:

```
$ adb shell ls -ld /system_ext /system/system_ext
lrw-r--r-- 1 root root   18 /system_ext -> /system/system_ext
drwxr-xr-x 10 root root 4096 /system/system_ext
```

That is precisely the layout a Google GSI uses (since Android 11 a GSI carries
`system_ext` *inside* `system.img`). Another sign this device was built GSI-shaped.

## 6. Verified boot — the AVB chain, decoded

`vbmeta` is AVB 1.2, `SHA256_RSA2048`, with `avbtool 1.2.0` as release string.
It contains **chain partition descriptors**, so the chain is three levels deep:

```
vbmeta            (key sha1 cdbb7717…)   flags 0
├── chain → boot            (key 9d808b09…)
├── chain → vbmeta_system   (key fa41159a…)
│              └── hashtree: system   (root ea624841…)
│              └── hashtree: product  (root 208d846e…)
└── chain → vbmeta_vendor   (key 9577bc6c…)
               └── hashtree: vendor   (root c537d787…)
    plus hash descriptors for dtbo, vendor_boot
    plus hashtree descriptors for odm_dlkm, vendor_dlkm
```

Consequences:

- Replacing `system` invalidates the `system` hashtree root in **`vbmeta_system`**.
  You must re-flash `vbmeta_system` with verification disabled, *or* disable verification
  at the top of the chain, *or* boot with the bootloader unlocked and a vbmeta whose flags
  include `HASHTREE_DISABLED (2)`.
- Because the chain is rooted in `vbmeta`, flipping the flags in **`vbmeta`** alone is
  sufficient to disable verification for the whole chain (AVB propagates the flags from the
  top-level vbmeta). This is the lever we intend to use.
- `boot` is a **separate chain partition with its own key**. Flashing a modified `boot.img`
  needs the same treatment as `system`.

### 6.1 Key material — what we do and do not have

| Key | sha1 | Do we have it? |
|---|---|---|
| `vbmeta` (chain root) | `cdbb7717 7f731920 bbe0a0f9 4f84d903 8ae0617d` | **No.** OEM/customer private key. |
| `boot` chain | `9d808b09 95768d06 77fccb1e fcddb7cf 9e153d99` | **No.** |
| `vbmeta_system` | `fa41159a 5d696abd ef93176a 07d0b0d0 01263f01` | **No.** |
| `vbmeta_vendor` | `9577bc6c 0772975e cce93c4d 8a178662 c728dadf` | **No.** |
| OTA/recovery cert | `otacerts.zip` → `testkey.x509.pem` | **No** — Techvision's own key, despite the filename. |

Two very different stories there:

- **AVB** (what the bootloader enforces) is signed with a genuine, private OEM key. We
  cannot forge a valid signature. Every modification therefore requires *disabling*
  verification, not re-signing. Verified with `avbtool info_image` plus a manual
  comparison of the modulus against the cert in `otacerts.zip` — they do not match.
- **OTA/recovery package verification** uses `otacerts.zip`, which contains exactly one
  certificate — and despite being *named* `testkey.x509.pem` it is **not** the AOSP test key.
  It is a Techvision self-signed certificate:

  ```
  subject = C=zh, ST=Guangdong, L=Shenzhen, O=Huiweizhineng, OU=Ruanjian,
            CN=Bing, emailAddress=bing_wu@techvision.com.cn
  validity = 2023-03-31 .. 2050-08-16
  serial   = 4e:31:15:4b:d1:d7:8f:16:6f:7f:5c:b5:1c:93:d8:fb:2d:0c:03:a6
  ```

  (`Huiweizhineng` = 慧为智能 = Techvision Intelligent.) Byte comparison against the real
  AOSP `testkey.x509.pem` from `platform/build` confirms they differ (sha256
  `92543d0d…` vs `a4384ba8…`, 1476 vs 1675 bytes).

  **Consequence: we hold no private key that this device trusts.** Not for AVB, not for OTA,
  not for DSU. This is the single most important constraint on the whole project, and it is
  what makes `DSU` unlikely to work (see `03-gsi-explainer.md` §5.2).

For completeness, the four keys in the boot chain are all distinct:
`cdbb7717…` (vbmeta root), `9d808b09…` (boot), `fa41159a…` (vbmeta_system),
`9577bc6c…` (vbmeta_vendor), plus `c65febbe…` (the OTA cert). None are public keys we have
the private half of.

### 6.2 The GSI key hook in the fstab

Both `/vendor/etc/fstab.mt6789` and `/vendor/etc/fstab.mt8781` (they are identical) carry
this line:

```
system /system ext4 ro wait,slotselect,avb=vbmeta_system,logical,first_stage_mount,\
  avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
```

`avb_keys=` is the AOSP mechanism that lets `fs_mgr` verify `system` against **Google's
per-release GSI public keys** instead of the vendor's own chain. Its presence proves the
BSP was configured with GSI support in mind.

Two caveats, both checked:

- Only **Q (10), R (11), S (12)** GSI keys are listed. There is no `t-gsi` (13) or later,
  so an Android 13+ Google GSI will *not* satisfy this particular check.
- The keys themselves (`/avb/*.avbpubkey`) **do not exist on this device**. We unpacked
  both the `boot.img` ramdisk (Google generic, no `/avb`) and the 22 MB `vendor_boot`
  vendor ramdisk (MTK, no `/avb`). `ls /avb` on the running system: no such directory.
  So the `avb_keys` option is vestigial and will fall back to the `vbmeta_system` chain.

Conclusion: treat it as evidence of GSI intent, **not** as a working free pass.

## 7. Update mechanism: Virtual A/B

```
ro.build.ab_update            = true
ro.boot.slot_suffix           = _a
ro.boot.dynamic_partitions    = true
ro.boot.veritymode            = enforcing
ro.boot.veritymode.managed    = yes
ro.boot.vbmeta.device_state   = locked
ro.boot.verifiedbootstate     = green
ro.boot.flash.locked          = 1
```

`/dev/block/mapper/` contains `system_a-cow`, `product_a-cow`, `vendor_a-cow`,
`vendor_dlkm_a-cow` **and** `pl_a`, `pl_b` — the presence of snapshot COW devices plus
logical preloader partitions means this is **Virtual A/B (VAB)**, not legacy A/B.
`pl_a`/`pl_b` are the preloader exposed as dynamic partitions.

Practical impact: `fastboot` cannot flash a logical partition directly in bootloader mode;
you need **`fastbootd`** (`fastboot reboot fastboot`), which is userspace fastboot running
from the recovery ramdisk and which understands snapshot/COW and `resize-logical-partition`.

## 8. Filesystem and encryption

From `/vendor/etc/fstab.mt6789`:

```
/data  f2fs  ... fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized,
                  keydirectory=/metadata/vold/metadata_encryption, fsverity
```

- `/data` is **f2fs**, not ext4, with **file-based encryption v2** and the key directory on
  `metadata`, plus `fsverity`.
- `ro.crypto.state=encrypted`, `ro.crypto.type=file`.
- Consequence for GSI: a Google GSI supports f2fs `/data` fine, but you **must wipe
  `userdata` and `metadata`** when switching, because the FBE keys live in `metadata` and a
  new system image will not unwrap the old ones. This is expected and documented.

## 9. Hardware inventory (what a GSI has to keep working)

**Display** — 2000×1200 px, density 240 dpi (`ro.sf.lcd_density`), primary display
orientation `ORIENTATION_270` (i.e. the panel is mounted rotated; the GSI must be a tablet
GSI or the UI will come up sideways at 240 dpi — fixable with `wm size`/`wm density` and
the `ro.surface_flinger.primary_display_orientation` override).

**GPU / graphics** — `ro.hardware.egl=meow` (ARM Mali), `ro.hardware.vulkan=mali`,
`ro.opengles.version=196610` (GLES 3.2), composer HIDL **2.1**
(`ro.vendor.composer_version=2.1`). Vendor composer 2.1 works with all current GSIs, but
a 2.1 composer is the oldest thing in the stack — some newer GSIs assume composer 2.3/2.4
features. This is the most likely source of UI jank after a GSI install.

**Sensors** — 7 HAL sensors, exposed via `android.hardware.sensors@2.0-service.multihal-mediatek`:

| Sensor | Chip | Notes |
|---|---|---|
| accelerometer | `stk83xx_acc` (Sensortek STK83xx) | calibrated data in `persist` |
| light (ALS) | `stk3x3x_als` | auto-brightness |
| proximity | `stk3x3x_ps` | |
| significant motion, tilt, device orientation, uncalibrated accel | MTK | |

There is **no magnetometer, no gyroscope, no hall sensor** — so no compass, no proper
autorotate-from-gravity beyond the accelerometer, and no smart-cover support. A GSI cannot
add these; it simply won't see them.

**DRM** — Widevine via HIDL `android.hardware.drm@1.4-service.widevine`, with vendor
libraries `liboemcrypto.so`, `libtlcWidevineModularDrm.so` (Trustonic TEE integration) and
`liburee_meta_drmkeyinstall.so`, plus `libwvdrmengine.so` in `/vendor/lib64/mediadrm/`.
This is a **hardware-backed (TEE) Widevine implementation**, i.e. L1-class. Because the
HAL and the OEMMCrypto live in `/vendor`, they survive a system-only GSI swap — but whether
the *service level* stays L1 is the subject of `06-backup-and-risk.md`.

**Connectivity** — `persist.vendor.connsys.chipid=0x6789`, combo chip `mt6631_6635`,
Wi-Fi/BT firmware patch `240724112957000`. Wi-Fi only; `ro.vendor.mtk_ps1_rat=no`, no modem
image in the firmware package (`md1img` is referenced by fstab but absent), no SIM slot.
That removes the single biggest MTK GSI headache (telephony/IMS/RIL) entirely.

**Battery** — `charge_full_design=2940000 µAh` (2.94 Ah), Li-ion, currently 100%.
Marketing material for the T3 quotes ~7000 mAh; the fuel gauge reports 2940 mAh. Treat the
gauge number as authoritative and the marketing number as unverified.

**Storage** — UFS 2.2, 128 GB nominal, 109 GiB on `/data`. Measured ~896 MB/s sequential
read (UFS class). See §5.1 for why the scatter file's "EMMC" label is wrong.

## 10. What this all means for the GSI project

| Requirement | Status |
|---|---|
| Treble-enabled | ✅ `ro.treble.enabled=true` |
| Full VNDK isolation (can run *newer* GSI) | ✅ `namespace.default.isolated=true` |
| arm64 | ✅ `arm64-v8a` |
| Launched on Android 9+ | ✅ first API level 33 |
| Dynamic partitions | ✅ `super`, liblp v10.2 |
| A/B (actually Virtual A/B) | ✅ with COW snapshots |
| fastbootd reachable | ⚠️ **untested** — LK has fastboot, not yet exercised |
| Bootloader unlockable | ⚠️ **untested** — `sys.oem_unlock_allowed=1` but no `oem_unlock_allowed` setting present |
| Recovery path if it goes wrong | ✅ full OEM firmware + SP Flash Tool; MT6789 is a *V6* SoC, so entry is **preloader mode + signed `DA_BR.bin`**, not BROM |
| DRM / attestation preserved | ⚠️ vendor kept, but unproven |

The two open questions are both **bootloader-level**, and both are cheap to answer
non-destructively. See `07-procedure.md` §1.
