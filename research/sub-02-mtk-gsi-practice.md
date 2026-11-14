# MT8781 (Helio G99) / Android 13 on vendor API 31 — practical MTK mechanics for installing an AOSP GSI

Scope: practical research layer only. Device facts (MT8781, A13 system on A12 vendor `ro.vendor.api_level=31`,
Treble, A/B boot/vbmeta/dtbo/vendor_boot/init_boot, `super` = 0x240000000 = 9 GiB, dm-verity enforcing,
AVB 1.2, bootloader LOCKED, kernel 5.10.209-android12 GKI split) are taken as given.

Every claim below carries the URL it came from. Where no source exists, it is marked **[inference]** or
**[no source / conflicting]** — do not launder those into fact.

---

## 1. Does a retail MTK device expose `fastboot` and `fastbootd`?

**Yes, both — but they are two different flash targets and MTK treats them differently.**

* `fastboot` = the bootloader (LK on MTK). `fastbootd` = a userspace daemon, normally living in the
  recovery image, that the bootloader boots via the BCB command `boot-fastboot`.
  "Fastbootd is the name of a userspace daemon and mode. To support fastbootd, the bootloader must
  implement a new boot control block (BCB) command of boot-fastboot."
  <https://source.android.com/docs/core/architecture/bootloader/fastbootd>
* Entering fastbootd: `adb reboot fastboot` (system) or `fastboot reboot fastboot` (bootloader).
  `getvar is-userspace` returns `yes` in fastbootd, `no` in the bootloader (same page).
* You *need* fastbootd for anything inside `super`: "partitions needed by the bootloader can't be made
  dynamic… `system` is now mounted by first-stage init, which resides in the ramdisk"
  <https://source.android.com/docs/core/ota/dynamic_partitions/implement>
* MTK devices do reach fastbootd in practice. A documented MTK (Helio G88 / Redmi Note 11) GSI install
  uses exactly `adb reboot bootloader` → `fastboot reboot fastboot` → `fastboot flash system …`, and
  explains why: "the bootloader doesn't have access to the inner logical partitions in the super
  partition (e.g. system), which we need access to."
  <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergö/>
  (typo-safe URL: <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>)
  Hovatek gives the same advice for an MTK Tecno: "just use `fastboot reboot fastboot` /
  `fastboot delete-logical-partition product` …"
  <https://www.hovatek.com/forum/thread-47900.html>
* MTK LK also carries vendor `oem` sub-commands that are not in AOSP. Documented example on an MTK
  Redmi: `fastboot oem cdms` ("isn't very well documented, but it seems to stop dm-verity issues from
  happening"), issued right after `fastboot flash super` and `fastboot format userdata`, before reboot.
  <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>
  (A tool exists specifically to mine these strings out of LK binaries: chkndrp/fastboot-oem-extractor,
  "hidden `fastboot oem` commands from firmware. LK, BFBF, SSSS (MediaTek)".)

**What LK does and does not do (be precise here):**

* LK only sees GPT partitions. `fastboot flash system` in *bootloader* mode fails/misbehaves on a
  dynamic-partition device; the logical name exists only inside `super`. Use fastbootd.
  <https://source.android.com/docs/core/ota/dynamic_partitions/implement>
* `fastboot flashing unlock` is part of the standard LK unlock flow; whether it is *enabled* is an
  OEM/LK policy question, not a protocol one. This device's LK contains the full string set for
  `fastboot flashing unlock` and reports `sys.oem_unlock_allowed=1` (given), so the OEM path is the
  one to try first — do not start with `mtk da seccfg unlock`.
* **Not supported / unreliable on MTK in the field** [community-reported, no primary doc]:
  – `fastboot reboot fastboot` when the recovery/BCB path is broken or when the device boots recovery
    from `vendor_boot`+`init_boot` rather than a `recovery` partition — LK then just reboots to system
    or loops. Fallbacks seen in the wild: `fastboot reboot recovery`, then use fastbootd from there.
  – `fastboot getvar max-download-size` returning **`no`** — this is the single most common MTK
    fastbootd breakage. Symptom:
    `couldn't parse max-download-size 'no'` / `Sending 'system_a' (2511884 KB) FAILED (remote: 'Invalid size')`
    <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>
    Consequence: you cannot push a multi-GB image in fastbootd on such a build. Workaround is the
    `super.img` route (§4) — flash the whole `super` in **bootloader** mode, where the limit applies
    to the image as a whole and fastboot sparsifies automatically.
* MTK LK generally has **no** `fastboot fetch`, no `fastboot flash vendor_boot:default`, no
  `fastboot oem lock`/`oem unlock` guarantees, and no useful `getvar all` for logical partitions
  (logical-partition introspection lives in fastbootd). **[inference from the AOSP fastbootd command
  table + observed MTK behaviour; not individually documented per-SoC.]**

**Practical MTK entry sequence**

```bash
adb devices                     # must be authorised; enable OEM unlocking + USB debugging first
adb reboot bootloader
fastboot devices
fastboot getvar is-userspace    # expect: no
fastboot getvar current-slot    # expect: a
fastboot getvar super-partition-name   # expects "super" (no slot suffix on virtual-A/B)
fastboot reboot fastboot        # → fastbootd
fastboot getvar is-userspace    # expect: yes
fastboot getvar max-download-size      # if "no" → abort this route, go to §4
```

---

## 2. Correct fastboot sequence: A/B + dynamic partitions + `super`

AOSP's own GSI flash recipe (this is the canonical sequence to quote):

> 1. boot to fastboot, unlock bootloader
> 2. devices supporting fastbootd: `fastboot reboot fastboot`
> 3. `fastboot erase system` ; `fastboot flash system system.img`
> 4. `fastboot -w`
> 5. `fastboot reboot-bootloader`
> 6. `fastboot --disable-verification flash vbmeta vbmeta.img`
> 7. `fastboot reboot`

<https://source.android.com/docs/setup/build/gsi> (§ Requirements for flashing GSIs)

And for the classic MTK/small-`super` failure:

```
Resizing 'system_a'  FAILED (remote: 'Not enough space to resize partition')
```

the documented fix is `fastboot delete-logical-partition product_a` (suffix must match the slot).
Same page, same section.

**Assembled sequence for this tablet** (AOSP steps + community additions; each line annotated):

```bash
# 0. backups first — see §5 (mtkclient readback) and §4 (dump super)
fastboot getvar current-slot                 # a
fastboot oem device-info                     # if LK supports it; else skip

# 1. disable AVB *before* touching system, on ALL vbmeta partitions that chain descriptors
fastboot --disable-verity --disable-verification flash vbmeta        vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system  vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor  vbmeta_vendor.img

# 2. go to userspace fastboot
fastboot reboot fastboot
fastboot getvar is-userspace                 # must be yes

# 3. free space in the system group, then flash
fastboot delete-logical-partition product_a  # AOSP-documented space reclaim
fastboot delete-logical-partition product_b  # only if it exists
fastboot resize-logical-partition system_a 0 # optional: shrink to min first
fastboot erase system
fastboot flash system system.img             # 2–3 GB; needs working max-download-size

# 4. wipe the encryption/metadata state the GSI cannot read
fastboot -w
fastboot erase metadata                      # MTK/AVB metadata; -w does not always cover it
# mtkclient equivalent if fastboot -w is unusable: mtk e userdata,metadata,md_udc,cache
#   (https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md)

# 5. back to bootloader, clear verity state (MTK-specific), reboot
fastboot reboot-bootloader
fastboot oem cdms                            # MTK: clears dm-verity state, poorly documented
fastboot reboot
```

**Do `vbmeta_system` / `vbmeta_vendor` need patching on MTK? Yes, almost certainly on this device.**
Reason, from AOSP: with dynamic partitions and chained AVB, "the bootloader expects to find a vbmeta
footer at the end of the `system` and `vendor` partitions. Because these partitions are no longer
visible to the bootloader (they reside in `super`), two changes are needed: Add `vbmeta_system` and
`vbmeta_vendor` partitions…"
<https://source.android.com/docs/core/ota/dynamic_partitions/implement> (§ AVB configuration changes)
The device already has `vbmeta_system_a/_b` and `vbmeta_vendor_a/_b` (given), so the chains exist and
replacing `system` invalidates the `vbmeta_system` chain. Disabling only top-level `vbmeta` leaves the
chain descriptor intact and you get a verity failure, not a boot.
Community guidance agrees, and ties it to kernel version: "Kernel 5.4 and/or newer devices (check if
your device has vbmeta_system via stock rom…): `fastboot --disable-verity --disable-verification flash
vbmeta_system vbmeta_system.img`" — kernel 5.10 here.
<https://xdaforums.com/t/ultimate-gsi-guide-for-beginners-where-to-find-gsi-how-to-port-gsi-how-to-flash-gsi-etc.4695349/>

Note on flags: the *official* Google recipe uses only `--disable-verification` on `vbmeta`
(<https://source.android.com/docs/setup/build/gsi>), while community recipes use
`--disable-verity --disable-verification` on `vbmeta` **and** `vbmeta_system`. On an MTK device with
dm-verity enforcing, use both flags. You can also flash Google's prebuilt
`vbmeta.img` (linked from <https://developer.android.com/topic/generic-system-image>) — it is an
empty/disabled vbmeta, equivalent in effect for AVB purposes.

---

## 3. MTK GSI bootloop causes and fixes

Ranked by how often they actually bite on MT8781-class hardware:

1. **`super` too small / resize refused** — `Not enough space to resize partition`. GSIs are 2–3 GB,
   stock `system` is often 1.3–1.5 GB. Fix: delete `product_a`/`product_b` (AOSP-documented) or rebuild
   `super` (§4). Evidence: same error on an MTK device with a 1.39 GB `system_a` and a 2.57 GB GSI.
   <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>
   <https://source.android.com/docs/setup/build/gsi>
2. **`max-download-size` = `no` in MTK fastbootd** → `FAILED (remote: 'Invalid size')`, image never
   lands, device boots stock or loops. Fix: §4 (`fastboot flash super`) — same source.
3. **AVB/dm-verity not fully disabled.** Symptom: "dm-verity … system is corrupted" bootloop, or
   "Your device is corrupt" then power-off. Fix: both flags on `vbmeta` **and** `vbmeta_system`
   (+`vbmeta_vendor` where present), then `fastboot oem cdms` on MTK. Sources as in §2; Hovatek's
   canonical note: "disable dm_verity so to avoid any bootloop issue"
   <https://www.hovatek.com/forum/thread-34082.html> and
   <https://www.hovatek.com/blog/dm_verity-is-probably-why-that-twrp-flash-ends-in-a-bootloop/>
4. **`vendor_dlkm` dropped or wiped.** `vendor_dlkm` holds the GKI vendor kernel modules; a GSI never
   provides it. If you build a `super.img` without it (or wipe it), vendor modules fail to load and the
   device dies before the GSI UI. **Keep the stock `vendor_dlkm_a` (and `odm_dlkm_a`) byte-identical**
   in any rebuilt `super`. This is why the worked MTK example keeps `vendor` and only drops `product`/
   `mi_ext`. <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>
   **[inference on the failure mode; the "keep it" rule is what the working recipe does.]**
5. **Encryption/metadata mismatch.** GSI cannot decrypt stock `/data`; leaving `metadata` (AVB/keystore
   rollback state) stale also breaks boot. `fastboot -w` twice is a real MTK pattern ("Ensure to perform
   `fastboot -w` twice (it seems it doesn't …)")
   <https://github.com/phhusson/treble_experimentations/issues/1661>, and mtkclient's documented unlock
   flow wipes `userdata,metadata,md_udc,cache`
   <https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md>.
6. **Wrong slot / stale slot metadata.** Flashing `system` while the boot slot is `b` (or vice versa)
   gives a clean flash and a black boot. Check `fastboot getvar current-slot`, then
   `fastboot --set-active=a` **before** the flash, and remember virtual-A/B keeps one copy of each
   logical partition in `super` — the suffix you flash must match the active slot.
7. **`persist` / NVRAM damage — the MTK-specific killer.** `persist`, `nvdata`, `nvram`, `protect1/2`,
   `seccfg`, `md1img` are not in `super` and a GSI never touches them; but a *format-all* SP Flash Tool
   run does. Result is not a bootloop, it is "NV data is corrupted", unknown baseband, no IMEI:
   "after it attempted to boot a few times, I got the dreaded 'NV data is corrupted' error"
   <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>
   Never use SP Flash Tool "Format All + Download" on this tablet; use "Download Only"/"Firmware
   Upgrade" with the OEM scatter, and dump `persist`/`nvdata`/`nvram` first.
8. **SELinux / vendor policy mismatch.** AOSP GSIs are enforcing with the AOSP policy; some MTK vendor
   blobs need permissive or a policy patch. Community crutch is the "Permissiver" zip (sets permissive
   at boot), aimed at older/oddly-Treblized devices
   <https://xdaforums.com/t/ultimate-gsi-guide-for-beginners-where-to-find-gsi-how-to-port-gsi-how-to-flash-gsi-etc.4695349/>.
   **[no MT8781-specific report found.]**
9. **Sparse vs raw image confusion.** `fastboot` accepts sparse images (it will sparsify a raw one
   itself); SP Flash Tool does **not** — it writes the file bytes literally into the partition.
   A `lpmake --sparse` output therefore must be `simg2img`-converted to raw before an SPFT flash.
   **[inference from how SPFT writes partitions; not stated in any doc I found — treat as "do it, it's
   free".]** The worked MTK example builds its super without `--sparse` for the SPFT-style path
   <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>.
10. **Missing `init_boot` awareness.** On GKI devices with a separate `init_boot` (this tablet has one),
    ramdisk/first-stage init lives there, not in `boot`. Flashing a GSI does not require touching it,
    but a "GSI won't boot, first-stage init fails" symptom usually means someone flashed a mismatched
    `boot`/`init_boot`, not that the GSI is wrong. **[inference from the AOSP GKI split; no MTK doc.]**

Conflicting / missing community data, explicitly flagged:
* Whether MTK fastbootd honours `resize-logical-partition system_a <size>` upward: one MTK report says
  it would not work and only `delete-logical-partition` freed space
  <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>; Hovatek's
  advice is to *create* a tiny `product` and delete the real one
  <https://www.hovatek.com/forum/thread-47900.html>. Both are MTK, different SoCs. Untested on MT8781.
* No MT8781/Helio G99-specific bootloop matrix exists. Searches surfaced Helio G88/G99 tablets only in
  generic "GSI works/bootloops" threads (e.g. <https://xdaforums.com/t/discontinued-gsi-14-lineageos-21-light.4653433/page-8>)
  with no reproducible fix list.

---

## 4. Non-fastboot route: rebuild `super.img`, flash with SP Flash Tool

This is the route that survives a locked/dysfunctional fastbootd. Nothing here needs an unlocked
bootloader for the *build*; it does need unlock to *boot* a modified image (or SPFT "Firmware Upgrade"
with the OEM signed images, which is what the manufacturer supports).

### 4.1 Tools and where to get them on Linux

| Tool | Purpose | Where |
|---|---|---|
| `lpunpack` | split `super.img` into `system_a.img`, `vendor_a.img`, … | Arch: `android-tools` (`usr/bin/lpunpack` — verified in the package file list <https://archlinux.org/packages/extra/x86_64/android-tools/files/>); Debian/Ubuntu: **not** packaged as `lpmake`/`lpunpack` — `android-sdk-libsparse-utils` only ships `simg2img`/`img2simg`/`append2simg`/`simg_dump` <https://packages.debian.org/trixie/all/android-sdk-libsparse-utils/filelist> |
| `lpmake` | build a new `super.img` | same as above; otherwise build from AOSP <https://android.googlesource.com/platform/system/extras/+/master/partition_tools/> or take prebuilt binaries <https://github.com/northumber/android-partition-tools_prebuilt_binaries>, or `cvd-host_package.tar.gz` from any `userdebug` build on <https://ci.android.com/builds/branches/aosp-master/grid> |
| `lpdump` | read the existing `super` metadata (groups, slot count, sizes) — **do this before building** | same package |
| `img2simg` / `simg2img` | raw ↔ sparse | Debian: `android-sdk-libsparse-utils` |
| `imjtool` | alternative unpacker that *prints the group schema* (`lpunpack` can't) | <http://newandroidbook.com/tools/imjtool.html> |

Arch's `android-tools` ships `lpmake lpunpack lpadd lpdump lpflash img2simg simg2img ext2simg` — confirmed
from the package file listing above.

### 4.2 Procedure

```bash
# 0. get a raw, exact copy of super (mtkclient readback — see §5)
mtk r super super_stock.bin            # or: mtk rl out/   (all partitions)

# 1. read the stock layout. This is the source of truth for group names, slot count and sizes.
lpdump super_stock.bin
#   → metadata slots, "super" block device size (must match 0x240000000 = 9663676416),
#     group names (e.g. main_a / main_b, or qti_dynamic_partitions_a/_b, or *_dynamic_partitions_a),
#     and each partition's size + attributes (readonly/none)

# 2. unpack
mkdir work && cd work
lpunpack ../super_stock.bin .

# 3. (only if the GSI is bigger than the stock system partition + reclaimed space)
#    Either drop product entirely, or shrink product to free room. Do NOT touch
#    vendor_a / vendor_dlkm_a / odm_dlkm_a.
ls -l system_a.img vendor_a.img vendor_dlkm_a.img odm_dlkm_a.img product_a.img

# 4. convert the GSI to the same format you will pack (raw ext4 is expected by lpmake)
#    GSI zips contain system.img (raw) — keep it raw; sparse only if you will flash via fastboot
#    img2simg GSI-system.img system_a.img    # only for the fastboot/--sparse path

# 5. repack. Copy the group names / metadata-slots / device-size *from lpdump*, do not invent them.
lpmake \
  --metadata-size 65536 \
  --super-name super \
  --metadata-slots 3 \
  --device super:9663676416 \
  --group <GROUP_A>:<sum-of-slot-A-partitions> \
  --partition system_a:readonly:<size>:<GROUP_A> \
  --partition system_ext_a:readonly:<size>:<GROUP_A> \
  --partition product_a:readonly:<size>:<GROUP_A> \
  --partition vendor_a:readonly:<size>:<GROUP_A> \
  --partition vendor_dlkm_a:readonly:<size>:<GROUP_A> \
  --partition odm_dlkm_a:readonly:<size>:<GROUP_A> \
  --image system_a=./system_a.img \
  --image vendor_a=./vendor_a.img \
  --image vendor_dlkm_a=./vendor_dlkm_a.img \
  --image odm_dlkm_a=./odm_dlkm_a.img \
  --output ./super_new.img
```

Notes that matter, each with its source:

* `--device super:` must be the **exact** partition size; `--metadata-slots` must match the device
  (2 for A/B, 3 if the stock dump says 3). Worked MTK example used `--metadata-slots 3`
  <https://blog.senyuuri.info/posts/2022-04-27-patching-android-super-images/>.
* `--group <name>:<size>` size = sum of the partitions in that group, and for **legacy A/B** the group
  max must be `super/2 − overhead` (here 4.5 GiB − 4 MiB); for **virtual A/B** the group may span the
  whole device and you add `--virtual-ab`. AOSP rule: "For A/B launch devices, the sum of maximum sizes
  of all groups must be: `BOARD_SUPER_PARTITION_SIZE / 2 − overhead`"; "A reasonable overhead is 4 MiB".
  <https://source.android.com/docs/core/ota/dynamic_partitions/implement>
* Tell virtual-A/B from legacy-A/B with `lpdump` (does `super` contain only `_a` partitions and no `_b`
  copies?) and `adb shell getprop ro.virtual_ab.enabled`. This tablet has `_a/_b` for boot/vbmeta/dtbo/
  vendor_boot/init_boot but a single 9 GiB `super` — consistent with **virtual A/B** (one copy of the
  logical partitions, snapshots during OTA). **[inference from the given partition list — confirm with
  `lpdump` before building.]**
* Worked MTK example with virtual A/B and full-size groups on both slots (Redmi Note 11, MTK):
  `lpmake --metadata-size 65536 --super-name super --sparse --virtual-ab --metadata-slots 3
   --device super:8226127872 --force-full-image --group <G>_a:8226127872 --group <G>_b:8226127872
   --partition mi_ext_a:readonly:282624:<G>_a … --image … --output ./super.img`
  <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>
* Don't use `--sparse` unless you are flashing with fastboot; SPFT needs raw (§3.9). Same blog builds
  without `--sparse` for the flash-tool path, and notes you must drop `--sparse` to inspect the result
  with `lpdump`.
* Sanity-check the result with `lpdump super_new.img` and compare group/partition names against
  `lpdump super_stock.bin`; a name mismatch gives a boot-time "failed to mount /system" or an
  unbootable `super`.

### 4.3 Flashing it with SP Flash Tool v6

```text
SP Flash Tool v6 → Download tab
  Scatter-loading file: MT6789_Android_scatter.txt   (OEM, from the firmware package)
  Mode: "Download Only"  (never "Format All + Download" — kills nvdata/nvram/persist, §3.7)
  Untick everything except: super
  Location of super: super_new.img (RAW, not sparse)
  → Download
```

* SPFT flashing a hand-built `super.img` by "just selecting the scatter file, then picking the new
  super.img" is reported working on MTK
  <https://xdaforums.com/t/editing-system-img-inside-super-img-and-flashing-our-modifications.4196625/>
  — with the caveat in that same thread that the user saw "successfully flashed, but no changes", which
  is the classic stale-`metadata`/stale-slot symptom (§3.5), not a flash failure.
* This is also the "Firmware Upgrade" path the manufacturer documents, so the DA/auth handshake is
  already solved for this model — that matters for §5.
* After flashing: boot to stock recovery and factory-reset (or `fastboot -w` if fastboot works), because
  `/data` is still encrypted with the old keys.
* To restore: same SPFT flow with the stock `super.img` from the firmware package. Keep it.

---

## 5. mtkclient: BROM/preloader, readback, and what it cannot do here

### 5.1 The MT6789 caveat — this is the important part

mtkclient's README states, verbatim:

> **MT6781, MT6789, MT6855, MT6886, MT6895, MT6983, MT8985**
> These chipsets use a new protocol called V6 and the bootrom is patched. You need to use the
> `--loader` option and a proper loader from the `Loaders/V6` directory. Bootrom won't work, you need
> to use preloader mode (no hw buttons pressed, just connect). On some devices, preloader is
> deactivated, but you can reactivate it by running `adb reboot edl`.

<https://github.com/bkerler/mtkclient>

So for MT8781/MT6789: **BROM mode is not the entry point.** Preloader mode is. `adb reboot edl` is the
way in when the preloader is disabled — which requires a bootable Android (it is, today).

### 5.2 Real MT6789 handshake, from a user log

```
Preloader - CPU: MT6789/MT8781V(MTK Helio G99)
Preloader - SBC enabled: True
Preloader - SLA enabled: False
Preloader - DAA enabled: True
Preloader - Mem read auth: False
Preloader - Mem write auth: False
Mtk - We're not in bootrom, trying to crash da...
Exploitation - Crashing da...
Preloader - [LIB]: upload_data failed with error: Unknown: 0x1d18
```

<https://github.com/bkerler/mtkclient/issues/86>

Read that as: reads/writes are *not* auth-gated at preloader level on this SoC (`Mem read auth: False`),
but the DA upload needs the right DA + a working exploit, and the pre-built generic path can fail
(`0x1d18`). The maintainer-side answer in the same thread: "V6 BROMs are patched against kamakiri2 …
MTKClient now supports both heapbait and carbonara (DA1/2) exploits, meaning that with a valid DA
loader, there's a chance you can still use it on secure V6 devices by passing `--loader DA_BR.bin`. In
most cases, OEMs include a DA file within the stock firmware." A later reply in the same issue confirms
success on an MT6789 device (Infinix Hot 40 Pro) with that method.

### 5.3 Readback / full dump (Linux)

```bash
pipx install git+https://github.com/bkerler/mtkclient.git

# entry: power off, hold vol-up+vol-down (or vol-up + power), plug USB; release when the tool reacts
mtk printgpt                                   # confirm GPT is readable
mtk rl out/ --skip=userdata                    # dump every partition (fast, ~GBs)
mtk r super super_stock.bin                    # just super
mtk r boot_a,vbmeta_a,vbmeta_system_a,vbmeta_vendor_a,lk_a,seccfg,persist,nvdata,nvram \
      boot_a.img,vbmeta_a.img,vbmeta_system_a.img,vbmeta_vendor_a.img,lk_a.img,seccfg.bin,persist.bin,nvdata.bin,nvram.bin
mtk rf flash.bin                               # whole-flash dump (DA mode only)
mtk reset
```

<https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md> (commands `rl`, `r`, `rf`, `printgpt`,
`reset`); a clean worked Linux example incl. the exact partition list you get from `mtk rl`:
<https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/>

For this tablet, dump at minimum: `super`, `boot_a`, `init_boot_a`, `vendor_boot_a`, `dtbo_a`,
`vbmeta*_a`, `lk_a`, `seccfg`, `persist`, `nvdata`, `nvram`, `md1img_a`, `proinfo`, `protect1/2`.

### 5.4 What mtkclient can and cannot do on a *locked* Android 13 MTK device

Can (with a working DA + exploit, preloader mode):
* read partitions / full flash (`mtk r`, `mtk rl`, `mtk rf`) — reads are not auth-gated on MT6789 per the
  log above;
* write/erase individual partitions (`mtk w`, `mtk e`), including `super`, `boot`, `vbmeta*`;
* `mtk e metadata,userdata,md_udc` to reset encryption state;
* `mtk da seccfg unlock` / `lock` — the *documented* unlock primitive
  <https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md>.

Cannot / do not rely on:
* **Reuse the session with SP Flash Tool.** "Modern DAs will shut down the phone when you disconnect it
  from the PC, so you can't really use SP Flash Tool" after an mtkclient DA session on V6
  <https://github.com/bkerler/mtkclient/issues/86>. Do one tool per session.
* **BROM-mode attacks.** kamakiri/amonet/hashimoto are patched on V6; `mtk dumpbrom` is not the path
  for MT6789 (README, issue #86).
* **`seccfg` unlock reliability on V6/DAA.** `seccfg` is hash/OTP-protected (v4 layout, `lock_flag` 3 =
  unlocked, `critical_lock_flag` 1 = unlocked; the hash is recomputed with a per-chip SEJ key that only
  exists in BROM/preloader) — the mechanism is understood, but success on a given V6 device is
  device-dependent, and the DA must accept the write
  <https://xdaforums.com/t/how-does-mtkclient-patch-seccfg-to-unlock-the-bootloader.4746261/>.
  **[conflicting]**: there is no MT6789-specific confirmation either way in the threads I read; the
  MT6789 confirmations in issue #86 are about *flashing/reading*, not about seccfg unlock.
* Since this tablet's LK implements the real `fastboot flashing unlock` flow and
  `sys.oem_unlock_allowed=1`, **unlock via fastboot first**. Use `mtk da seccfg unlock` only if the OEM
  flow is refused — and snapshot `seccfg` before you try.

---

## 6. Do Android 14/15/16/17 GSIs work on a vendor API level 31 device?

**What Google actually documents** (and what it does not):

* Device eligibility, per the app-developer GSI page: bootloader unlocked, "Fully Treble-compliant",
  launched with Android 9+; cross-version support is decided by VNDK compliance, checked with
  `getprop ro.treble.enabled` and `ld.config.version_identifier.txt` (`namespace.default.isolated`).
  **There is no per-GSI-release "minimum vendor API level" table on that page.**
  <https://developer.android.com/topic/generic-system-image>
* The compatibility rule is stated in the vendor-API-level doc: "The LLNDK is backward compatible, so
  any vendor image that is less than or equal to this API level can be flashed with this system image"
  — i.e. `ro.llndk.api_level` of the GSI must be ≥ the vendor's API level. On Android 14 QPR3+ both
  values are `YYYYMM` dates (`ro.board.api_level`, `ro.vendor.api_level`, `ro.llndk.api_level`); on
  Android 13 and earlier they are integers.
  <https://source.android.com/docs/core/architecture/api-flags>
* VNDK is **deprecated starting with Android 15**: no VNDK APEX for 15, `ro.vndk.version` removed from
  vendor/product built for 15 — but "VNDK APEXes with VNDK version 14 or lower, which are required to
  support existing vendor images" are kept, and "LL-NDK isn't part of the VNDK".
  <https://source.android.com/docs/core/architecture/vndk>
  Practical reading: Android 15/16 GSIs still carry legacy VNDK APEXes to serve pre-15 vendors, so a
  vendor API 31 device is *within* the supported envelope by design; it is not guaranteed feature-complete.
* Google's own tooling does enforce a check, host-side, with this message: "GSI build is incompatible
  with this device: GSI `ro.llndk.api_level` is undefined. Either select a GSI from the same build id as
  the device vendor…, or flash device vendor to a release build whose codename is 'REL' and select a GSI
  build whose platform version >= device vendor version."
  <https://xdaforums.com/t/flashing-prevented-due-to-gsi-incompatibility-why.4704993/>
  That is Android Flash Tool/`flash.android.com` policy (and it fires on mismatched build IDs, including
  on Pixels), **not** a fastboot/AVB gate. Plain `fastboot flash system` will happily write an
  incompatible GSI and then bootloop. **[inference: no AOSP source found for a device-side block.]**

**Practical verdict for vendor API 31 + MT8781, by release:**

| GSI | Verdict on a vendor-31 MTK device | Evidence |
|---|---|---|
| Android 13 (T) | Baseline; the safest target. | GSI target table: devices launching with Android 13 use `gsi_$arch` <https://source.android.com/docs/setup/build/gsi> |
| Android 14 (U) | Usually boots on MTK vendor-31 hardware; "stick to A13 or A14" is the working advice from an MTK GSI install. | <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/> |
| Android 15 (V) | **Booted** on the same MTK device (LineageOS 22.1 GSI inside a rebuilt `super`), with a known regression: "Android 15 GSI's currently have issues with the fingerprint readers". VNDK deprecation is the mechanism behind "works but feature gaps". | same blog; <https://source.android.com/docs/core/architecture/vndk> |
| Android 16 / 17 | **No evidence either way for MT8781.** Nothing in AOSP's GSI docs raises the vendor floor; nothing in the community threads I found confirms a boot on vendor 31. Expect breakage from vendor-API-202404-era HAL expectations (e.g. VTS assertions of `vendor API level >= 202404` appear in `hardware/interfaces`) and from MTK HALs that assume framework internals. Treat as **unverified / likely-partial**, not as documented-incompatible. | <https://android.googlesource.com/platform//hardware/interfaces/+/aa8ebc7c39bf4d62b53cba826f03fb5cd915a222%5E1..aa8ebc7c39bf4d62b53cba826f03fb5cd915a222/> |

**Missing information, flagged:** Google publishes no table of "GSI version → minimum vendor API level".
Anyone who quotes one is inferring from LLNDK/VNDK behaviour. The defensible statement is: *newer GSIs
are required to remain compatible with older vendor images via LLNDK backward compatibility plus legacy
VNDK APEXes, but feature-level breakage (fingerprint, camera, RIL, brightness) is common and
SoC-specific.* Also: **do not** expect `ro.vendor.api_level` to change — it is frozen at the device's
first API level (<https://source.android.com/docs/core/architecture/api-flags>), so a vendor-31 device
stays vendor-31 no matter which GSI you flash.

---

## 7. Recommended decision tree for this tablet

1. **Unlock via LK**: `adb reboot bootloader` → `fastboot flashing unlock` (LK supports it,
   `sys.oem_unlock_allowed=1`). Verify with `fastboot getvar unlocked`.
2. **Dump everything with mtkclient** (`mtk rl out/ --skip=userdata`) before any write. Non-negotiable:
   `super`, `seccfg`, `persist`, `nvdata`, `nvram`, `vbmeta*`, `lk_a`.
3. **Try the fastbootd route once**, with `getvar max-download-size` as the go/no-go:
   `fastboot reboot fastboot` → if `yes`, follow §2 (disable all three vbmeta, delete `product_a`,
   flash `system`, `-w`, erase `metadata`, `oem cdms`, reboot). If `no` → abort, go to 4.
4. **Otherwise rebuild `super.img`** (§4) with the GSI as `system_a`, stock `vendor_a`,
   `vendor_dlkm_a`, `odm_dlkm_a`, and `product` dropped or shrunk; flash it with SPFT v6
   "Download Only" (super only), then factory-reset from recovery.
5. **GSI choice**: Android 13 or 14 first (predictable), Android 15 only if fingerprint loss is
   acceptable, Android 16/17 untested on this SoC.
6. **Rollback**: stock `super.img` + stock `boot`/`vbmeta*` via SPFT; keep the OEM scatter file and the
   full firmware package untouched.

---

## Sources (all fetched during this research)

1. <https://source.android.com/docs/core/architecture/bootloader/fastbootd> — fastbootd, BCB, command table.
2. <https://source.android.com/docs/core/ota/dynamic_partitions/implement> — super/dynamic partitions, AVB chaining, group sizing, A/B group ≤ super/2.
3. <https://source.android.com/docs/setup/build/gsi> — GSI flash recipe, `delete-logical-partition product_a`, GSI targets per launch version.
4. <https://developer.android.com/topic/generic-system-image> — GSI eligibility (unlocked, Treble, Android 9+), VNDK cross-version check.
5. <https://developer.android.com/topic/generic-system-image/releases> — GSI download matrix (A13 → A17 QPR3).
6. <https://source.android.com/docs/core/architecture/api-flags> — `ro.vendor.api_level`, `ro.llndk.api_level`, LLNDK backward compatibility.
7. <https://source.android.com/docs/core/architecture/vndk> — VNDK deprecation in Android 15; legacy APEXes kept.
8. <https://github.com/bkerler/mtkclient> — V6 chipsets incl. MT6789 need `--loader` + preloader mode; `adb reboot edl`.
9. <https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md> — `r/rl/rf/printgpt/e/w/reset`, unlock flow.
10. <https://github.com/bkerler/mtkclient/issues/86> — MT6789 handshake log, DA/SLA/DAA reality, heapbait/carbonara, SPFT-after-DA limitation.
11. <https://lochnair.net/2025/01/15/Flashing-a-custom-ROM-on-my-Redmi-Note-11-China-evergo/> — end-to-end MTK GSI install: fastbootd, `Invalid size`, lpunpack/lpmake/`--virtual-ab`, `fastboot flash super`, `oem cdms`, A15 FOD regression, NV-data loss.
12. <https://www.hovatek.com/forum/thread-47900.html> — MTK super resize / delete-logical-partition practice.
13. <https://www.hovatek.com/forum/thread-34082.html> — MTK GSI bootloop ↔ dm-verity; minimal fastboot recipe.
14. <https://www.hovatek.com/blog/dm_verity-is-probably-why-that-twrp-flash-ends-in-a-bootloop/> — dm-verity bootloop explainer.
15. <https://xdaforums.com/t/ultimate-gsi-guide-for-beginners-where-to-find-gsi-how-to-port-gsi-how-to-flash-gsi-etc.4695349/> — vbmeta_system on kernel ≥5.4, fastbootd sequence, Permissiver, bootloop triage.
16. <https://xdaforums.com/t/editing-system-img-inside-super-img-and-flashing-our-modifications.4196625/> — lpunpack/lpmake worked example; SPFT flashing a custom super.img.
17. <https://blog.senyuuri.info/posts/2022-04-27-patching-android-super-images/> — imjtool group schema, lpmake flag semantics, `shared_blocks`/`unshare_blocks`.
18. <https://xdaforums.com/t/flashing-prevented-due-to-gsi-incompatibility-why.4704993/> — host-side `ro.llndk.api_level` incompatibility gate.
19. <https://xdaforums.com/t/how-does-mtkclient-patch-seccfg-to-unlock-the-bootloader.4746261/> — seccfg v4 layout, SEJ-key hashing, why V6 unlock is device-dependent.
20. <https://archlinux.org/packages/extra/x86_64/android-tools/files/> — lpmake/lpunpack/lpdump/simg2img in `android-tools`.
21. <https://packages.debian.org/trixie/all/android-sdk-libsparse-utils/filelist> — Debian ships only sparse utils.
22. <https://android.googlesource.com/platform/system/extras/+/master/partition_tools/> — canonical lpmake/lpunpack source.
23. <https://github.com/phhusson/treble_experimentations/issues/1661> — MTK GSI bootloop, `fastboot -w` twice.
