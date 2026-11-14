# Procedure — from stock to GSI (and back)

> **Status:** every command marked ✅ was executed against the device and its output is
> quoted verbatim. Commands marked ⬜ are the planned sequence for the flashing phase and
> have **not** been run — we are still in the research phase and nothing has been written to
> the tablet.

---

## Phase 0 — Build the safety net first (⬜ but essential)

Do not skip this. Everything else assumes you can put the tablet back exactly as it is.

### 0.1 What you already have

`FW/TVE1070M_US_MT8781_A13_WIFI_user_20241016.212541/` is a **complete** SP Flash Tool
firmware package: preloader, lk, boot, vendor_boot, dtbo, tee, all the MTK firmware
partitions, a 4.9 GB `super.img`, and `MT6789_Android_scatter.txt`.

`Tool/SP_Flash_Tool_V6/SPFlashToolV6.exe` plus `Tool/MTK-Driver-v5.2307` is the matching
flasher. The supplied `Firmware Update Operation Guide.pdf` describes exactly one flow:
**Download → `download_agent/flash.xml` → Type = `Firmware Upgrade` → connect a powered-off
device over USB-A to USB-C**.

That is a **Windows-only** tool. See §9.

### 0.2 Why SP Flash Tool is a real safety net

On MediaTek, the **preloader** runs from a dedicated boot partition (UFS LU0/LU1, or eMMC
boot1/boot2 on eMMC variants) before any Android partition is consulted, and behind it sits
the **BROM** (boot ROM) in the SoC. This layer does not care what is on `super`, `boot`, or
`vbmeta`.

⚠️ **But this SoC's BROM is patched.** MT6789/MT8781 is on mtkclient's **V6** list: the
classic BROM exploit path (hold a volume key, get `0e8d:0003`) does **not** work. The entry
point is **preloader mode** with a **signed Download Agent** — the `DA_BR.bin` shipped in the
firmware package. So the recovery door exists and works, it is just one layer up and needs
the OEM's DA. Do not assume the generic "hold Vol+ and pray" recipe.

Practical consequence: **a bad `system` flash is not a brick.** It is an hour of waiting for
a 5 GB transfer.

⚠️ The one thing that *does* threaten this: flashing a **different device's** firmware, or
flashing with a mismatched scatter/preloader. Verify the package's own hashes and never mix
files between firmware versions.

### 0.3 Validate the package before you need it

```bash
# inventory and integrity
sha256sum FW/TVE1070M_*/images/*.img > firmware.sha256
# confirm the scatter matches this device
fastboot getvar product          # -> tb8781p1_64_wifi  (must equal scatter 'project')
```

✅ Confirmed on this unit: `product: tb8781p1_64_wifi`, matching
`general.project: tb8781p1_64_wifi` in the scatter, and
`version-bootloader: tb8781p1_64_wifi_8c8e89655_20241016125`.

---

## Phase 1 — Back up the per-unit partitions (⬜, needs preloader-mode access)

This is the part people skip and regret. Details of *what* and *why* are in
`06-backup-and-risk.md`; here is the mechanism.

`adb` cannot read these: the build is `ro.build.type=user`, `ro.debuggable=0`, so there is no
root, and `persist`/`nvdata`/`proinfo`/`seccfg` are not readable by `shell`.

You therefore need one of:

### Option A — SP Flash Tool "Readback" (Windows, uses the bundled tool)

`Tool/SP_Flash_Tool_V6/Readback` is present, and `read_efuse.xml` / `readback_ui_bak.xsd`
ship with the tool — the vendor clearly expects readback to be usable.

1. Open `SPFlashToolV6.exe` → **Readback** tab.
2. Add a readback entry per partition: set the start address and length from the scatter
   (`linear_start_addr` and `partition_size`), name the output file.
3. Power the tablet off, click **Readback**, then connect USB.

Minimum set to capture: `persist`, `nvdata`, `nvcfg`, `nvram`, `proinfo`, `protect1`,
`protect2`, `seccfg`, `otp`, `expdb`, `frp`, `metadata`, `boot_para`, `dram_para`.

The offsets are already tabulated in `appendix-a-partition-map.md`, so the readback entries
can be filled in mechanically.

### Option B — `mtkclient` on Linux (the practical route)

⚠️ **MT6789/MT8781 is special: BROM mode is not the entry point.** mtkclient's own README
lists MT6781/MT6789/MT6855/MT6886/MT6895/MT6983/MT8985 under **V6**: *"These chipsets use a
new protocol called V6 and the bootrom is patched. You need to use the `--loader` option and
a proper loader from the `Loaders/V6` directory. Bootrom won't work, you need to use
preloader mode (no hw buttons pressed, just connect). On some devices, preloader is
deactivated, but you can reactivate it by running `adb reboot edl`."*
— <https://github.com/bkerler/mtkclient>

So: **do not** hold volume keys hoping for `0e8d:0003` BROM. Use **preloader mode** instead,
and supply a Download Agent.

**You already have the right DA.** The firmware package ships one:
`FW/…/images/download_agent/DA_BR.bin`. mtkclient's maintainer recommends exactly this —
*"in most cases, OEMs include a DA file within the stock firmware"* — and there is a
confirmed success on an MT6789 device with that method
(<https://github.com/bkerler/mtkclient/issues/86>).

```bash
# Entry: with the tablet POWERED OFF, just plug in USB (no buttons).
DA=/work/FW/TVE1070M_US_MT8781_A13_WIFI_user_20241016.212541/images/download_agent/DA_BR.bin

mtk --loader $DA printgpt | tee out/gpt-before.txt     # confirms read access + real sizes
mtk --loader $DA rl out/ --skip=userdata               # dump everything except userdata
mtk --loader $DA r persist out/persist.bin             # or one at a time
mtk --loader $DA da rpmb r                             # RPMB: rollback counters, secure state
```

Two verified gotchas, both learned the hard way on this unit (see `08-findings-log.md`
F25/F26):

- **Do not pass `--vid` / `--pid`.** In mtkclient 2.1.4 the explicit path builds a *list*
  where the matcher expects a *dict*, so any `--vid`/`--pid` silently matches nothing. The
  default ID table already covers `0x2000` (preloader) and `0x0003` (BROM).
- **`adb reboot edl` is not a substitute for a cold start.** It *does* reach preloader mode
  (`0e8d:2000`, confirmed with timestamps), but mtkclient's handshake fails there
  (`Status: Handshake failed, retrying...`) because that entry is MTK's emergency-download
  mode, not the preloader download protocol. It is a good way to prove the mode exists, and
  the right entry point for SP Flash Tool — not for mtkclient.

So the physical step is unavoidable for the backup: **fully power off, then connect USB, no
buttons.** Buttons matter only for BROM mode, which is patched on this V6 SoC anyway.

Both entry points sit on the same USB ID space, so tell them apart with `lsusb`:
`0e8d:201c` is the normal Android/fastboot interface (what we see today), and the preloader
presents differently once the tablet is off and reconnecting.

A real MT6789 handshake log (different unit) reads:

```
Preloader - CPU: MT6789/MT8781V(MTK Helio G99)
Preloader - SBC enabled: True
Preloader - SLA enabled: False
Preloader - DAA enabled: True
Preloader - Mem read auth: False
Preloader - Mem write auth: False
```

`Mem read auth: False` is the encouraging line — reads are not auth-gated at preloader level,
so a dump should be possible even with DAA on. `DAA enabled: True` is why the signed OEM
loader is required.

⚠️ **One tool per session.** Modern MTK DAs shut the phone down when the host disconnects, so
you cannot hand a live session from mtkclient to SP Flash Tool. Finish the dump, `mtk reset`,
then reconnect for anything else.

⚠️ **Test this before you commit.** If you cannot read `persist` at all, you have no backup,
and the unlock becomes a one-way bet on Widevine L1. That is a stop sign, not a detail.

### Verify the dumps

```bash
ls -l out/persist.bin            # must be 55264 KiB / 0x35f8000 bytes
head -c 4 out/persist.bin | xxd  # ext4 superblock magic 53EF at offset 0x438
```

Store the dumps **off the device** and in two places. They are unit-specific and
irreplaceable.

---

## Phase 2 — Unlock the bootloader (⬜, one-way door)

✅ **Verified**: the bootloader will allow it.

```
$ fastboot flashing get_unlock_ability
(bootloader) unlock_ability is true
```

and `fastboot getvar all` reports `unlocked: no`, `secure: yes`, `current-slot: a`,
`slot-count: 2`, both slots `successful: yes`.

If `unlock_ability` had said `false`, you would first have to enable *Settings → About →
tap Build number ×7 → Developer options → OEM unlocking*. On this unit that toggle does not
appear to exist as a setting (`settings get global oem_unlock_allowed` returns `null`) while
the property `sys.oem_unlock_allowed=1` is already set, so the flag is presumably baked in at
the factory.

```bash
adb reboot bootloader
fastboot flashing unlock
```

⚠️ **`fastboot flashing unlock` is destructive.** It wipes `userdata` (and with it everything
in `/sdcard`) and turns `verifiedbootstate` from `green` to `orange`, permanently, until you
re-lock. Back up photos/documents first.

The LK binary contains the on-device confirmation flow, so expect a **menu on the tablet
screen**:

```
Unlock bootloader?
  Yes (Volume UP or Volume Down): Unlock(may void warranty).
  No  (Auto exit after 5 seconds): Do not unlock bootloader.
```

Press a volume key to confirm. Then:

```bash
fastboot getvar unlocked        # -> unlocked: yes
```

Re-locking later (`fastboot flashing lock`) is only safe if every partition is back to stock
**and** signed with the OEM key. Do not re-lock while running a GSI — it will brick the
device into a boot loop that only SP Flash Tool can fix.

---

## Phase 3 — Choose and prepare the GSI (⬜)

See `05-image-options.md` for the candidates and their trade-offs. Mechanics:

### 3.1 Check the image before flashing it

Most GSI downloads are distributed as `system.img` (raw ext4) or as a sparse image, sometimes
inside a zip. Normalise it:

```bash
unzip -o gsi.zip
file system.img                     # "Linux rev 1.0 ext4 filesystem data" == raw
# if it is sparse:
simg2img system.img system-raw.img && file system-raw.img
```

A GSI `system.img` must be **raw ext4** for `fastboot flash system`. `fastboot` will chunk
the transfer automatically (this device reports `max-download-size: 0x4000000`, 64 MiB).

### 3.2 Decide about `product`

`system_a` is **1663 MiB**. Deleting `product_a` frees **2186 MiB** and is the standard fix
for "Not enough space to resize partition". It is safe here:

- the GSI carries `system_ext` *inside* `system.img`;
- this device has no real `system_ext` partition (`/system_ext` is a symlink to
  `/system/system_ext`);
- the only OEM app in `product` is `cn.com.techvision.sound`, an audio-tuning utility.

If you want to keep it, check sizes first:

✅ `partition-size:product_a` = `0x889EA000` = 2292 MiB,
`partition-size:system_a` = `0x67F2A000` = 1663 MiB,
`super` = `0x240000000` = 9216 MiB with 4473 MiB free.

---

## Phase 4 — Flash (⬜)

```bash
# 0. from Android, confirm the starting state
adb shell getprop ro.boot.verifiedbootstate     # green
adb reboot bootloader
fastboot getvar unlocked                        # must be "yes" (Phase 2)
fastboot getvar current-slot                    # a

# 1. disable AVB *first*, while still in bootloader fastboot
fastboot --disable-verity --disable-verification flash vbmeta vbmeta-flags3.img

# 2. switch to userspace fastboot (logical partitions live here)
fastboot reboot fastboot
fastboot getvar is-userspace                    # "yes"      <- verified live

# 3. make room in the system group
fastboot delete-logical-partition product_a     # frees 2186 MiB
fastboot delete-logical-partition product_b     # exists in metadata (0 extents)
fastboot resize-logical-partition system_a 0    # 0 = take all remaining group space

# 4. write the GSI
fastboot erase system
fastboot flash system system.img

# 5. wipe the encryption state the new system cannot read
fastboot -w
fastboot erase metadata

# 6. clear MTK's own dm-verity state, then boot
fastboot reboot bootloader
fastboot oem cdms
fastboot reboot
```

### Go/no-go checks before you start writing

Two `getvar`s catch the most common MTK fastbootd failures *before* anything is modified:

```bash
fastboot getvar max-download-size
# THIS DEVICE: 0x4000000 (64 MiB)          <- good
# known MTK failure: returns "no", and fastboot then dies with
#   "couldn't parse max-download-size 'no'" / "Invalid size" on a multi-GB image

fastboot getvar is-userspace
# must be "yes" in fastbootd
```

If `max-download-size` returns `no`, stop — the fastbootd route cannot carry a 2–3 GB image on
that build, and you must use Phase 7 (SP Flash Tool) instead. On this tablet it reports
`0x4000000`, so fastboot will chunk the transfer correctly.

### About step 1 — the vbmeta reality on *this* device

Generic MTK GSI guides tell you to patch **three** vbmeta images (`vbmeta`, `vbmeta_system`,
`vbmeta_vendor`). **On this tablet that is impossible, and the reason matters.**

Verified by querying the bootloader directly:

```
$ fastboot getvar partition-size:boot_a            -> 4000000        (known)
$ fastboot getvar partition-size:vbmeta_a          -> 800000         (known)
$ fastboot getvar partition-size:dtbo_a            -> 800000         (known)
$ fastboot getvar partition-size:vbmeta_system_a   -> (empty)
$ fastboot getvar partition-size:vbmeta_vendor_a   -> (empty)
$ fastboot getvar partition-size:tee_a             -> (empty)
$ fastboot getvar partition-size:gz_a              -> (empty)
```

LK exposes only a subset of the GPT to fastboot. `vbmeta_system_a`, `vbmeta_vendor_a`,
`tee_a` and `gz_a` are **not addressable**, so `fastboot flash vbmeta_system …` has nothing
to write to. (They do exist in the GPT — see `appendix-a-partition-map.md` — the bootloader
simply doesn't publish them.)

That leaves two levers, and we use both:

1. **Top-level `vbmeta_a`** — the one partition we can flash. AVB treats
   `HASHTREE_DISABLED`/`VERIFICATION_DISABLED` in the top-level vbmeta as global, and
   `vbmeta` is the chain root here, so this *should* cover `system` transitively.
2. **`fastboot oem cdms`** — "clear dm-verity status", an MTK-specific LK command. Confirmed
   present in this device's `lk.img`:

   ```
   clear_dm_verity_status
   get_dm_verity_status
   avb.managed_verity_mode
   Error clearing avb.managed_verity_mode.
   [FASTBOOT] Start reset dm-verity status.
   oem cdms
   ```

   This matters because `ro.boot.veritymode.managed=yes` — MTK runs its own managed verity
   state on top of AVB, so clearing the AVB flags alone may not be enough.

**Verified 2026-11-13 with `avbtool` against the shipped images — AVB is fully enabled:**

```
vbmeta.img         Algorithm: SHA256_RSA2048   Flags: 0   chains -> boot, vbmeta_system, vbmeta_vendor
vbmeta_system.img  Algorithm: SHA256_RSA2048   Flags: 0   hashtree over system, product
vbmeta_vendor.img  Algorithm: SHA256_RSA2048   Flags: 0   hashtree over vendor
```

`Flags: 0` means verification **and** hashttree verification are on, and the chain root is signed
with Techvision's key (`cdbb77…`), which we do not hold.

**Consequence, stated plainly:** on a **locked** bootloader the top-level flag patch cannot work,
because the bootloader verifies the `vbmeta` *signature* before it reads the flags — patching
`0 → 3` invalidates that signature, so the patch is refused before its content is ever
considered. **Unlocking is a hard prerequisite for any GSI on this unit, not an optimisation.**
The Widevine L1 trade-off in `06-backup-and-risk.md` therefore applies to the whole GSI route.

One useful nuance that does survive: **attempting** a `Download Only` flash while still locked
does not change the lock state (`verifiedbootstate` stays `green`). If the device refuses to boot
the swapped `system`, reflashing the OEM package with `Firmware Upgrade` restores it exactly. So
the L1 risk attaches specifically to the **unlock**, not to trying the flash — which makes a
locked-bootloader attempt a cheap experiment rather than a gamble.

**If it still refuses to boot**, the fallback is to write the patched `vbmeta_system.img` /
`vbmeta_vendor.img` **by scatter address** with SP Flash Tool (Phase 7). Those images are in
the firmware package, and `avb_flags.py` can patch them the same way as `vbmeta` — the only
obstacle is that fastboot can't reach them.

### About the `vbmeta-flags3.img` we flash

We do **not** hold the OEM's AVB private key, so we cannot produce a validly signed vbmeta.
What we can do is take the OEM's own `vbmeta.img` and set its `flags` field to `3`
(`HASHTREE_DISABLED | VERIFICATION_DISABLED`), leaving the chain-partition descriptors for
`boot`, `vbmeta_system` and `vbmeta_vendor` intact.

This is exactly what `work/tools/avb_flags.py` does, and the result is verified:

```
$ python3 work/tools/avb_flags.py vbmeta.img --flags 3 --out vbmeta-flags3.img
wrote vbmeta-flags3.img: flags 0 -> 3 (HASHTREE_DISABLED=True, VERIFICATION_DISABLED=True)

$ avbtool info_image --image vbmeta-flags3.img
Public key (sha1):  cdbb77177f731920bbe0a0f94f84d9038ae0617d
Algorithm:          SHA256_RSA2048
Flags:              3
Descriptors:
    Chain Partition descriptor:  ... boot, vbmeta_system, vbmeta_vendor all intact
```

The RSA signature no longer matches. On an unlocked bootloader that is tolerated (the device
boots "orange"); on a locked one it would be refused. This is why Phase 2 must come first.

---

## Phase 5 — First boot and the fixes you will probably need (⬜)

A GSI on a 2000×1200 240 dpi landscape panel with a 2.1 composer will boot, but the UI will
usually be wrong. Expect, in rough order of likelihood:

```bash
# density / resolution
adb shell wm size 2000x1200
adb shell wm density 240

# navigation bar (Google documents this one for GSI)
adb shell cmd overlay enable-exclusive com.android.internal.systemui.navbar.gestural

# verify the vendor side came up intact
adb shell getprop ro.treble.enabled
adb shell getprop ro.vendor.api_level            # should still be 31
adb shell dumpsys sensorservice | head -20       # expect 7 sensors
adb shell ip link show wlan0                     # Wi-Fi present?
adb shell dumpsys media.mediadrm                 # DRM service alive?
```

Known likely problems and where to look:

| Symptom | Likely cause | Fix |
|---|---|---|
| Bootloop, no ADB | AVB still enforcing, or `metadata` not wiped | re-flash flags=3 vbmeta; `fastboot erase metadata` |
| Boots to fastboot only | `system` image incompatible (wrong arch/sparse) | re-check `file system.img`, re-flash |
| Wi-Fi won't enable | `nvdata`/`persist` MAC or calibration | restore dumps; `connsys_wifi` repopulates from `/vendor/firmware` |
| Sensors dead | `persist` lost | restore `persist` from Phase 1 |
| Display sideways | panel rotation | `ro.surface_flinger.primary_display_orientation` override |
| Play Store missing | you flashed pure AOSP, not GMS | use a GMS or LineageOS GSI |
| Everything works but janky | composer 2.1 limits | no fix without a vendor update; try a lighter GSI |

---

## Phase 6 — Rollback (⬜)

Three levels, cheapest first.

1. **Back to the previous system, no reflash:** if you kept slot B intact, switch slots —
   though with Virtual A/B and a wiped `metadata` this usually does not survive. Fastest
   reliable route is level 2.
2. **Reflash stock via fastboot** (bootloader unlocked, fastboot + fastbootd work):
   flash `boot`, `vendor_boot`, `dtbo`, `vbmeta`, `vbmeta_system`, `vbmeta_vendor`, `lk`,
   then push `super.img` back and re-create the logical partitions. Tedious.
3. **Reflash stock via SP Flash Tool** (always works, Windows): the OEM flow from the PDF —
   `Firmware Upgrade` with `download_agent/flash.xml`. This also rewrites the partition table,
   so **it destroys the per-unit partitions** — which is exactly why Phase 1 exists.

After a stock reflash, re-lock if you want `green` back, but only from a fully stock state.

---

## Phase 7 — The Windows/SP-Flash-Tool route, if fastboot fails

If at some point fastbootd is unavailable (e.g. after a bad `boot`/`vendor_boot` flash), you
cannot use the Phase 4 sequence. The recovery is to build a `super.img` that already contains
the GSI and flash it with SP Flash Tool.

Mechanism:

1. Unpack the stock `super.img` into its parts and rebuild with the GSI substituted:

```bash
simg2img super.img super.raw
lpunpack super.raw out/                 # -> system_a.img, vendor_a.img, product_a.img, ...

lpmake --metadata-size 65536 --super-name super \
  --metadata-slots 3 \
  --virtual-ab \
  --device super:9663676416 \
  --group main_a:9663676416 --group main_b:9663676416 \
  --partition system_a:readonly:0:main_a --image system_a=system.img \
  --partition system_b:readonly:0:main_b \
  --partition vendor_a:readonly:0:main_a --image vendor_a=out/vendor_a.img \
  --partition vendor_dlkm_a:readonly:0:main_a --image vendor_dlkm_a=out/vendor_dlkm_a.img \
  --partition odm_dlkm_a:readonly:0:main_a --image odm_dlkm_a=out/odm_dlkm_a.img \
  --output super-new.img
```

Four things in that command are load-bearing and easy to get wrong:

- **`--virtual-ab`** is mandatory. The stock super reports `Header flags: virtual_ab_device`
  (confirmed with `lpdump`), and a rebuild without this flag produces metadata that does not
  declare Virtual A/B — the bootloader will not treat it as the device it expects. Note that
  this also relaxes the usual legacy-A/B constraint that a group must be ≤ half of `super`;
  with `--virtual-ab` the full 9663676416 bytes are addressable.
- **`--metadata-slots 3`** must match the stock value (stock prints `Metadata slot count: 3`,
  not the default 2).
- **`--device super:9663676416`** must match `ro.boot`/`fastboot getvar partition-size:super`
  exactly (`0x240000000`).
- **`--group` names** must be the stock names, `main_a`/`main_b` — copy them from `lpdump`,
  do not invent them.

Also: **produce a raw image, not a sparse one.** SP Flash Tool wants raw here; `simg2img` on
the output is the wrong direction. If you are flashing through fastboot instead, that path
wants sparse (`img2simg`), which is the opposite — don't mix the two up.

Verify the result before flashing it:

```bash
lpdump super-new.img | head -8      # must show "Header flags: virtual_ab_device"
```

2. Flash `super-new.img` (+ the flags=3 `vbmeta`) with SP Flash Tool in **Download Only**
   mode, selecting only those partitions in the scatter.

All the tools referenced here are in the project container (`lpunpack`, `lpmake`, `lpdump`,
`simg2img`, `avbtool`) — see `work/docker/Dockerfile` and `README.md` §Tooling.

⚠️ `lpmake` is **not** packaged on Debian; it had to be built from source
(`LonelyFool/lpunpack_and_lpmake`, vendored, needs `zlib1g-dev`). That is a real
reproducibility trap and is documented in `08-findings-log.md`.

---

## Phase 8 — The zero-risk test: DSU (⬜, recommended before Phase 4)

Before unlocking anything, try booting a GSI **without flashing**:

```bash
simg2img system.img system_raw.img
gzip -c system_raw.img > system_raw.gz
adb push system_raw.gz /sdcard/Download/
adb shell am start-activity \
  -n com.android.dynsystem/com.android.dynsystem.VerificationActivity \
  -a android.os.image.action.START_INSTALL \
  -d file:///sdcard/Download/system_raw.gz \
  --el KEY_SYSTEM_SIZE $(stat -c%s system_raw.img) \
  --el KEY_USERDATA_SIZE 8589934592
```

✅ DSU is present on this device: `com.android.dynsystem` is installed,
`/system/etc/init/gsid.rc` exists, `gsi_tool status` prints `normal`.

⚠️ DSU requires the image to be **signed by a key the device trusts**. This device's
`otacerts.zip` contains a single **Techvision self-signed certificate** — not Google's, and
not the AOSP test key despite the `testkey.x509.pem` filename
(`02-firmware-forensics.md` §6.1). So:

- a Google-signed GSI will be **rejected**;
- a GSI we sign ourselves would **also** be rejected, because we do not hold Techvision's
  private key.

**DSU is therefore probably blocked on this device.** It costs one attempt and a failure is
harmless, so it is still worth trying — but it is no longer the recommended first experiment.

If DSU is refused, the lowest-risk path becomes **Phase 7** (rebuild `super.img`, flash in
`Download Only` mode): no unlock, no `seccfg` change, so the TEE never sees an `orange` boot
state and Widevine L1 is never exposed. Keep the stock `super.img` ready to revert.

---

## §9 — What genuinely needs Windows

| Task | Windows needed? | Why |
|---|---|---|
| adb / fastboot / fastbootd flashing | No | works from Linux, verified |
| vbmeta flag patching | No | `avbtool` + `avb_flags.py` |
| `super.img` rebuild | No | `lpunpack` / `lpmake` in the container |
| **Backup of `persist`/`nvdata`/`seccfg`/`proinfo`** | **Probably not** | mtkclient in preloader mode with the OEM's own `DA_BR.bin` — MT6789 is a *V6* SoC, so this is the supported path. Fall back to SP Flash Tool Readback only if the DA is rejected. |
| **Full stock restore after a hard brick** | **Yes (or a Windows VM)** | `SPFlashToolV6.exe` is a Windows Qt binary and the MTK USB VCOM driver is Windows-only |

Everything in the "no" rows is already working here. The only Windows-only step is the
**worst-case** recovery, and even that has a Linux escape hatch: if the device still reaches
preloader mode, `mtk w` can write `super`/`boot`/`vbmeta` back by partition name without SP
Flash Tool.

A Windows VM with USB passthrough is sufficient for that; it does not need a physical machine.
The 5 GB firmware and the scatter file are already here, so the VM needs nothing but
`SPFlashToolV6.exe` and the drivers — both in `Tool/`.
