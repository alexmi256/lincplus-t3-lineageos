# Lincplus T3 (MT8781 / Helio G99) — GSI / bootloader-unlock backup & risk plan

Scope: Android 13 system over Android 12 vendor, A/B, `super` = 9 GiB dynamic, dm-verity
enforcing, AVB 1.2, bootloader LOCKED, Trustonic TEE (`libtlcWidevineModularDrm.so`,
`liboemcrypto.so`, `liburee_meta_drmkeyinstall.so`, `/vendor/mediadrm/`).

Every claim below is tagged:
**[DOC]** = vendor/Google/AOSP documentation · **[REP]** = reproducible community report
(linked) · **[FOLK]** = widely repeated but unverified/contradicted · **[?]** = uncertain,
treat as risk not fact.

---

## 0. Verdict up front

| Loss | Recoverable? |
|---|---|
| Widevine L1 keys (if TEE provisioning store is destroyed) | **No** — no user path to re-provision |
| Widevine L1 after unlock alone (TEE gates on boot state) | **No** until relock, and only if TEE re-opens; documented case where it never came back |
| Play Integrity DEVICE + STRONG | **Yes** — returns after full stock restore + relock |
| Play Integrity BASIC | Survives unlock (documented exception in verdict definition) |
| `persist`, `nvdata`, `nvram`, `proinfo`, `protect1/2`, `seccfg` | **Yes if you dumped them first**; no copy exists anywhere else |
| Wi-Fi/BT MAC, serial number | Yes from dump (or rewritable with SN Writer if you have MD1_DB/AP_DB) |
| Official OTA | Yes after stock restore + relock |
| OEM camera AI/wide-angle modes, stylus suite, Dolby UI, face-unlock UI | **No** — those live in `/system`/`/system_ext`, not `/vendor` |

**The single most important ordering rule:** the things you must back up are only readable
with root, and rooting requires the unlock that destroys them. Break the loop with
**mtkclient in preloader/BROM mode before you touch `seccfg`** (§4). Do not unlock first
"to get adb root and then back up".

---

## 1. Widevine / DRM

### 1.1 What L1 actually is

- L1 = decryption **and** decode inside the TEE/secure video path; required for HD/4K/HDR.
  L2 = crypto in TEE, decode outside. L3 = everything in software, "typically limited to SD".
  [DOC] https://developer.bitmovin.com/playback/docs/widevine-security-levels-in-web-video-playback
- Netflix states it plainly: *"To stream Netflix in HD on Android, your phone or tablet must
  support Widevine L1… If you see L3, you'll only be able to watch Netflix in SD. This can
  happen if your device is running a modified version of the Android operating system (OS)."*
  [DOC] https://help.netflix.com/en/node/23939

That single Netflix sentence is the whole HD-streaming risk in one line: Google's own
partner doc names a modified OS as a cause of L3.

### 1.2 Where the keys live — TEE, not a partition you can copy

- The Widevine **keybox** is provisioned at manufacture into **secure storage**, not into a
  user-readable partition. OEM flow (NXP, representative of the general model): either a
  plaintext keybox flashed with `fastboot oem provision-wv-keybox`, or an AES-ECB keybox
  encrypted with the SoC's Manufacturing Protection Public Key and decrypted *inside the
  TEE* before being written to secure storage. For Widevine **Provision 4.0 / RKP** devices
  "provisioning keybox is not needed" — keys are derived from a device-unique
  remotely-provisioned attestation identity.
  [DOC] https://docs.nxp.com/bundle/UG10158/page/topics/provisioning_widevine_l1_keybox.html
- RKP has shipped in AOSP since Android 12; the private keys are generated in
  secure hardware and never leave it. [DOC]
  https://source.android.com/docs/core/ota/modular-system/remote-key-provisioning
- Empirical: a researcher dumping `persist`, `protect1` and `protect2` with mtkclient on an
  MTK device found **no keybox** — keys were in the TEE. Older (pre-2020) devices *did*
  store `keybox.xml` in `/persist` and similar. [REP]
  https://www.reddit.com/r/androidroot/comments/1us2hby/keyboxxml_extraction/

**Conclusion:** Widevine L1 keys are device-unique and are *not* a file you can back up in
any useful sense on an Android 12+ TEE device. A raw dump of the partitions is encrypted to
a device-unique key; the same bytes restored to the same unit *may* work, restored to a
different unit never will.

### 1.3 What a GSI does vs what the unlock does

Mechanically, with `/vendor` preserved, a GSI **keeps the whole L1 path**:

```
framework MediaDrm (GSI /system)
  → android.hardware.drm@AIDL/HIDL  (vendor service, /vendor/bin/hw)
    → liboemcrypto.so              (/vendor/lib64, survives)
      → Trustonic TEE (tbase)      (tee_a, survives)
        → keybox in secure storage
```

So the GSI is *not* the thing that breaks L1 — the **unlock** is. Most OEM TEEs gate
secure-world services on the HLOS lock state (`ro.boot.verifiedbootstate` = orange when
unlocked, `ro.boot.flash.locked` = 0). [DOC]
https://source.android.com/docs/core/architecture/bootloader/locking_unlocking
When the TEE refuses the session, the CDM falls back to the software L3 path and
`drm_info`/DevCheck report L3. Because this varies by vendor TEE policy, some devices keep
L1 while unlocked and some don't — **[REP]** with wide variation.

### 1.4 The outcome you should plan for

Closest documented analogue, **same SoC family (MT6789 / G99), Lenovo Tab P11 2nd Gen
TB350XU**: user ran SP Flash Tool *Format All*, restored IMEI and serial successfully,
then found **L1 → L3**, Prime Video stuck at SD. He relocked the bootloader, unrooted and
reflashed stock firmware — **L1 did not come back**. [REP]
https://www.hovatek.com/forum/thread-47021.html

Same warning independently repeated for MTK tablet firmware packages: *"On both Flash Tool
V6 and SP Flash Tool V5, the download mode must be set to Firmware Upgrade. Do not use
Download Only, and never use Format All + Download."* [REP]
https://github.com/omixmobile/firmware

**So:** "L3 after GSI" is very often "L3 after unlock", and the widely reported pattern is
that it is **not** reliably fixed by reflashing stock. Reflashing restores the *code*, not
the *provisioning state* the TEE lost. Treat L1 as the thing you are gambling, not the GSI.

### 1.5 Can it be backed up at all?

Honest answer: **partially, as a lottery ticket, not as insurance.**

- No documented, supported backup/restore of Widevine L1 keys exists.
- What you *can* do is dump every partition that might hold the encrypted provisioning
  blob (`persist`, `protect1`, `protect2`, `nvdata`, `nvram`, `nvcfg`, `sec1`), keep them
  bit-exact, and if L1 drops, try restoring them on the **same unit** before reflashing
  stock. This has worked for some people and failed for others; **[?]**.
- What you must NOT rely on: the OEM firmware package. Its `nvdata`/`nvram` images are
  blanked placeholders — *"If its a nvdata/nvram file provided by your OEM's firmware
  files - then those are usually blanked out files."* [REP]
  https://github.com/phhusson/treble_experimentations/issues/1012

---

## 2. Play Integrity / SafetyNet

### 2.1 What the verdicts actually require (Android 13+, this device's system level)

From Google's own definitions [DOC]
https://developer.android.com/google/play/integrity/verdicts :

- **`MEETS_DEVICE_INTEGRITY`** — *"On Android 13 and higher, there is hardware-backed proof
  that the device bootloader is **locked** and the loaded Android OS is a **certified device
  manufacturer image**."*
- **`MEETS_BASIC_INTEGRITY`** — *"The device bootloader can be locked **or unlocked**, and
  the boot state can be verified or unverified. The device may not be certified."* Only
  requires that the attestation root of trust is provided by Google.
- **`MEETS_STRONG_INTEGRITY`** — requires `MEETS_DEVICE_INTEGRITY` **plus** security updates
  within the last year on *all* partitions, including an OS patch and a **vendor** patch.

### 2.2 Consequences for this device

| State | BASIC | DEVICE | STRONG |
|---|---|---|---|
| Stock, locked (today) | ✅ | ✅ | ✅ if patch level < 1 yr |
| Stock, **unlocked only** | ✅ | ❌ | ❌ |
| **GSI, relocked bootloader** | ✅ | ❌ (system is not a certified OEM image) | ❌ |
| GSI, unlocked | ✅ | ❌ | ❌ |

Two independent kills: unlocking alone kills DEVICE on A13+ (hardware-backed lock proof),
and a GSI kills it again even if you relock. **There is no configuration where DEVICE
survives a GSI.** BASIC survives both, which is why some apps keep working.

That also means **STRONG is unconditionally gone** — it can't be met without DEVICE.

`SafetyNet` is deprecated/retired; any app still calling it is reading the same signals.

### 2.3 Mitigations and their real caveats

| Tool | What it does | Caveat |
|---|---|---|
| **Play Integrity Fix / PIFork** | Spoofs `ro.build.fingerprint` + props of a certified device so DroidGuard returns DEVICE | Original `chiteroman` repo was **removed from GitHub**; only forks survive. Google bans fingerprints; you re-roll constantly. [REP] https://github.com/KOWX712/PlayIntegrityFix |
| **TrickyStore** | Hooks the **key-attestation certificate chain**; optionally injects a `keybox.xml` at `/data/adb/tricky_store/keybox.xml`; can also fake `security_patch` levels | Needs Magisk/KSU + Zygisk. **Went closed-source from v1.1.0.** [DOC] https://github.com/5ec1cff/TrickyStore |
| **Keybox injection** | Uses a *hardware* attestation keybox lifted from another device to get a real-looking Strong verdict | Keyboxes are **other people's private keys** — using a leaked one is unauthorised use of someone else's credentials; Google revokes them (public ones are banned within days); distributing them is a DMCA/CFAA-adjacent problem. [REP] reddit keybox thread above |
| **Property spoofing (`resetprop`)** | Cheap prop fixes | Not sufficient alone on A13+; DEVICE needs the hardware lock bit |

**Legal / ToS:** all of the above violate the Google Play Terms of Service and, for
apps that rely on Play Integrity (banking, DRM, payments), the app's own terms. Bypassing
an integrity/attestation control is a contractual violation and in some jurisdictions an
anti-circumvention issue. **[DOC-level: Play ToS; legal classification varies by
jurisdiction — this is not legal advice.]** None of it restores Widevine L1 — that's a
different subsystem and none of these tools touch it. **[FOLK]** any claim that
"TrickyStore gives you L1" — it does not.

**Realistic expectation:** PIF + TrickyStore with a *private, unrevoked* keybox can restore
DEVICE/STRONG for many apps. It does **not** restore Google Wallet tap-to-pay reliably
(Wallet runs additional server-side checks), and it does not restore Widevine L1.

---

## 3. MediaTek per-unit partitions — what's in them, what breaks, how to dump

**Sizes below** are from a published MT6xxx GPT whose layout matches this device almost
exactly (A/B, `super` = 9216 MB, same partition set) — [REP]
https://gist.github.com/Azkali/64a8acbd25697dde50dd4999b0c063c0 — **but verify on YOUR unit
with `python mtk.py printgpt` before trusting them.** Do not hardcode offsets.

| Partition | Size (verify) | Contains | If lost |
|---|---|---|---|
| `persist` | ~54 MB | Sensor calibration (`sns.reg`, accel/gyro/ALS/prox), touch & pen calibration, Wi-Fi/BT cal data, misc factory files; on pre-2020 devices sometimes DRM | Auto-rotate, auto-brightness, proximity, touch/pen accuracy wrong or dead. **Nothing regenerates it.** |
| `nvdata` | 64 MB | AP-side NV: runtime Wi-Fi/BT config, MAC-related data, feature flags | "nvdata corrupted", Wi-Fi/BT may fail to init, MAC unstable |
| `nvram` | 64 MB | MTK NVRAM: RF calibration, IMEI, **Wi-Fi MAC, BT MAC** | Dead or wrong-MAC Wi-Fi/BT; null IMEI (irrelevant here, no modem) |
| `nvcfg` | 32 MB | NV config template/metadata used to rebuild NV | NV rebuild failures |
| `proinfo` | 3 MB | Product info: model, region, **serial number**, sometimes Wi-Fi MAC | Serial = 0000000, wrong region/model → OTA & registration problems |
| `protect1` | 8 MB | Protected NV / carrier-radio data | NV corruption |
| `protect2` | 8 MB | Protected secure/TEE-adjacent storage (`protect_s`) | NV + possibly secure-storage problems **[?]** |
| `seccfg` | 8 MB | **Bootloader lock/unlock state + dm-verity state**, cryptographically tamper-protected | Stuck unlocked (or worse, won't boot / won't relock). Back up **before** unlock and again **after** relock. |
| `otp` | 48 MB | One-time-programmable factory area, effectively read-only | Nothing — **dump for the record, never restore** |
| `expdb` | 128 MB | Exception/crash database (aee_exp), panics, tombstones | Only crash history; regenerated |
| `frp` | 1 MB | Factory Reset Protection state | Only matters if a flash leaves FRP in a weird state; restoring it *clears* FRP (security-relevant) |
| `boot_para` | 1 MB | Boot-mode args passed LK → kernel | Usually benign, regenerated **[?]** |
| `para` | 512 KB | Boot params / panic log | Benign |
| `misc` | 512 KB | Bootloader control block (recovery cmds, OTA flags) | Benign, regenerated |
| `sec1` | 2 MB | Secondary security data / efuse shadow | **[?]** — dump it, cheap |
| `dram_para` | 25 MB | DRAM timing calibration | Possible no-boot / instability; some platforms re-calibrate |
| `flashinfo` | 16 MB | eMMC bad-block / wear metadata (last partition, sentinel) | **Never write to it** |
| `preloader` (boot1) | — | First-stage bootloader + BROM handshake | Hard brick territory; **also dump `--parttype=boot2`, which holds the serial number** |

**Where the Wi-Fi/BT MAC actually lives:** MTK writes it via NVRAM (`AP_CFG`) at factory
(SN Writer writes "Bluetooth / Wi-Fi Address, Ethernet Mac Address, DRMkey MCID and Serial
No." [REP] https://www.hovatek.com/forum/thread-12306.html). It is mirrored/duplicated in
some builds into `proinfo`. Dumping `nvram` + `nvdata` + `proinfo` covers it either way.

### 3.1 Dump with mtkclient (preferred — no unlock required)

Install: https://github.com/bkerler/mtkclient (README-USAGE has every command below:
https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md)

```bash
# 0. RECORD the GPT first — this is your map and your proof of sizes
python mtk.py printgpt | tee /backup/t3/gpt-before.txt

# 1. Targeted critical dump (do this BEFORE any seccfg write)
mkdir -p /backup/t3/parts
for p in persist nvdata nvram nvcfg proinfo protect1 protect2 seccfg otp \
         expdb frp boot_para para misc sec1 dram_para; do
  python mtk.py r "$p" "/backup/t3/parts/$p.img"
done

# 2. Preloader + the boot2 (serial number) area
python mtk.py r preloader /backup/t3/parts/preloader_boot1.img --parttype=boot1
python mtk.py r preloader /backup/t3/parts/boot2_serial.img      --parttype=boot2

# 3. RPMB (rollback/anti-rollback counters, some secure state)
python mtk.py da rpmb r        # writes rpmb.bin

# 4. Everything else that is cheap (skip super/userdata — huge)
python mtk.py rl /backup/t3/allparts   # dumps all partitions; delete super.bin/userdata.bin after
```

### 3.2 The V6 / secure-boot caveat — read this before you start

MT8781 is the tablet SKU of **MT6789**, and MT6789 is on mtkclient's **V6** list:
*"These chipsets use a new protocol called V6 and the bootrom is patched… Bootrom won't
work, you need to use preloader mode (no hw buttons pressed, just connect)."* [DOC]
https://github.com/bkerler/mtkclient — MTK preloaders for this family identify themselves
as `MT6789/MT8781V`.

Practical consequence:
- Kamakiri-style `--preloader` BROM exploit **will not work**.
- Use **preloader mode** (device off, no buttons, just plug in — or `adb reboot edl` if
  preloader is disabled) with a **DA loader**: `python mtk.py --loader MTK_AllInOne.bin …`
  or the DA/`DA_BR.bin` from the OEM firmware package.
- If DAA/SLA (secure boot) is armed, the DA must be the *signed* one and may need an auth
  file; SP Flash Tool readback in that case needs the Auth file loaded — [DOC]
  https://www.hovatek.com/forum/thread-439.html ("Ensure to use the Secure Boot DA (and
  Auth if requested)").
- **[?]** Whether this specific T3 unit is SLA-locked is unknown. **Test the dump path
  before you commit to the project.** If you cannot read `persist` at all, stop: you have
  no backup and therefore no safety net, and the unlock becomes a one-way bet on L1.

### 3.3 Dump with adb (only possible if already rooted — normally a chicken-and-egg)

```bash
adb shell 'ls -l /dev/block/by-name/'          # exact names + sizes on THIS unit
adb shell 'su -c "dd if=/dev/block/by-name/persist of=/sdcard/persist.img bs=1M"'
adb pull /sdcard/persist.img ./persist.img
```

This is only viable if you already have root **without** unlocking (a kernel exploit such
as CyberMeowfia — fragile, kernel-specific [REP]
https://github.com/NebuSec/CyberMeowfia), or on a second pass after you've decided to
unlock anyway. It is not the primary path.

### 3.4 Verify every dump (non-optional)

```bash
cd /backup/t3/parts
sha256sum *.img > SHA256SUMS

# 1. Dump twice, compare — readback errors are common on cheap eMMC
python mtk.py r persist /tmp/persist.2.img && cmp persist.img /tmp/persist.2.img

# 2. Not an all-0x00 or all-0xFF blank (a "successful" read of garbage is the #1 trap)
for f in *.img; do
  printf "%-22s " "$f"
  od -An -tx1 -N4096 "$f" | tr -d ' \n' | grep -qE '^(00+|ff+)$' && echo "BLANK!" || echo "ok"
done

# 3. Plausible content — MAC OUI should appear in nvram/proinfo
strings -n 6 nvram.img | grep -iE '([0-9a-f]{2}:){5}[0-9a-f]{2}'
xxd proinfo.img | head -40

# 4. Size sanity vs the GPT you captured
grep -E 'persist|nvdata|proinfo|seccfg' /backup/t3/gpt-before.txt
```

---

## 4. Other user-visible losses, and whether `/vendor` preservation saves them

| Feature | Where it lives | Survives GSI? |
|---|---|---|
| HD/4K streaming (L1) | TEE + `/vendor/lib*` + vendor DRM HAL | Path survives; **unlock** is what kills it (§1) |
| Google Wallet / tap-to-pay | Play Integrity DEVICE/STRONG + Wallet server checks | ❌ — needs locked BL + certified image; PIF/TrickyStore unreliable here |
| Banking apps | Play Integrity, many also root checks | ❌ until PIF/TrickyStore works; some detect anyway |
| Play Store "certified" status | Attestation | ❌ → some apps not installable; partially fixable by registering GSF ID at google.com/android/uncertified (fixes *availability*, not DRM) |
| Official OTA | AVB + dm-verity + locked state | ❌ while unlocked/modified. Returns after stock restore + relock (§5) |
| Hardware/enterprise attestation (MDM) | Keystore attestation cert carries boot state | ❌ — MDM will flag the device as compromised |
| Camera: basic stills/video | `/vendor` camera HAL | ✅ | 
| Camera: AI modes, wide-angle/macro switching, night mode, OEM app | `/system`/`/system_ext` OEM app + framework | ❌ — app is gone; multi-cam stream combos may not be exposed to 3rd-party apps |
| Stylus: pressure, tilt, palm rejection, stylus suite | vendor HAL + `/system_ext` service/app | HAL maybe ✅, **suite/UX ❌** |
| Auto-brightness, auto-rotate | vendor sensor HAL ✅ + `persist` cal ✅ | ✅ functionally, but the OEM brightness curve is a `/vendor/overlay` RRO that GSIs often ignore → **behaviour will differ** **[?]** |
| Audio DSP tuning / Dolby / EQ | `/vendor` blobs + `persist` ✅ | Effects survive at HAL level; the **Dolby/OEM UI app is in `/system` → gone**, so you may not be able to toggle it |
| Face unlock | vendor HAL + OEM `/system` components | often ❌ (UI/framework half missing) |
| Bluetooth codecs (aptX/LDAC), Wi-Fi 6 | `/vendor` licence blobs | ✅ |
| Sensors (raw) | vendor HAL + `persist` cal | ✅ if `persist` intact |

**Rule of thumb:** `/vendor` preservation saves *capability* (HALs, firmware, licences,
calibration). It does not save *features implemented as OEM apps or framework overlays*,
because those live in `/system` and `/system_ext`, which the GSI replaces.

---

## 5. Prioritised backup checklist

Do these **in order**. Steps 1–3 are read-only and change nothing.

### Phase 0 — Decide and de-risk (before any write)
1. **Ask whether you need to unlock at all.** GSI requires an unlocked bootloader, full
   stop. *"GSIs can only function on devices with… Bootloader is unlocked."* and *"GSIs
   don't support rollback, so you will need a recovery method and original system ROM."*
   [DOC] https://developer.android.com/topic/generic-system-image
   If the goal is only de-Googling or app testing, weigh it against permanently losing L1
   and DEVICE integrity.
2. **Record the current state**, for comparison after: 
   ```bash
   adb shell getprop ro.boot.verifiedbootstate   # green
   adb shell getprop ro.boot.flash.locked        # 1
   adb shell getprop ro.boot.veritymode          # enforcing
   adb shell getprop ro.build.fingerprint
   adb shell getprop ro.vendor.build.security_patch
   adb shell getprop ro.build.version.security_patch
   adb shell getprop ro.boot.slot_suffix
   ```
   Install **drm_info** and screenshot the Widevine line (**L1 or L3 right now?**). If it's
   already L3, the whole DRM objection evaporates — check before agonising.
   Also note `Settings → About → Build number` and the exact OTA level: you will need a
   stock package **at least this new** to relock without tripping AVB rollback.
3. **Verify the dump path works** (§3.2). If mtkclient cannot read `persist`, stop.

### Phase 1 — Read-only dumps (mtkclient, preloader/BROM, no unlock)
4. `printgpt` → `gpt-before.txt` (+ `ls -l /dev/block/by-name/` if you have any root).
5. Dump the 16 critical partitions (§3.1 step 1) + `preloader` boot1 + `boot2` (serial).
6. `da rpmb r` → `rpmb.bin`.
7. Dump `super` (or at least record it) — the OEM package covers it, but a bit-exact copy
   of what's on the device now is the only thing that matches your current OTA level.
   `python mtk.py r super super.img` (~9 GiB).
8. Back up `userdata` at the file level, not the partition level: photos, app data,
   `adb backup` is dead on A13 — copy `/sdcard` over MTP/`adb pull`, and export
   authenticator seeds / 2FA recovery codes **before** the wipe (the unlock wipes
   userdata by design — [DOC]
   https://source.android.com/docs/core/architecture/bootloader/locking_unlocking).

### Phase 2 — Verify (do not skip)
9. Re-dump 3 samples, `cmp` them.
10. Blank-check every image (§3.4 step 2).
11. `strings` sanity-check `nvram`, `proinfo`, `persist`.
12. Write a `MANIFEST.txt`: device serial, fingerprint, slot, date, tool version, sizes,
    sha256 of each file.
13. **Store 3 copies, 2 media, 1 off-site.** Encrypt (age/gpg) — `nvram`/`proinfo`/`persist`
    are device-unique identifiers and, on some builds, key material. Never commit these to
    a public repo.

### Phase 3 — Only now, the irreversible part
14. `python mtk.py da seccfg unlock` (or `fastboot flashing unlock`). This wipes userdata.
15. **Immediately re-dump `seccfg`** → `seccfg-unlocked.img`. Keep both lock states; you
    need the locked one to go back.
16. Flash: `fastboot reboot fastboot` (fastbootd) → `fastboot delete-logical-partition
    product` if you need room in `super` → `fastboot flash system <gsi>.img` →
    `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`
    (disabling verification is what lets an unsigned GSI boot; it also means your boot
    chain is no longer verifiable and OTA will refuse).
17. Boot, then **immediately** check: `drm_info` (L1/L3), Play Integrity via Play Store →
    Settings → About → Play Protect certification, and Wi-Fi/BT MAC in Settings.

### Phase 4 — If you want to go back
18. Flash the full OEM package with **"Download Only"/"Firmware Upgrade"**, never
    **"Format All"** (§1.4 — that is the documented L1 killer).
19. `python mtk.py da seccfg lock`, verify `ro.boot.verifiedbootstate` = `green`,
    `ro.boot.flash.locked` = `1`.
20. If the OEM package predates your installed OTA, AVB rollback may refuse the relock →
    you get a bootloop. **Capture the current build/OTA level in Phase 0** and get a
    matching package first.
21. Then re-test `drm_info`. If L3, try restoring `persist`/`protect1`/`protect2`/`nvdata`
    from your dumps (same unit), one at a time, then re-test. This is the lottery ticket.

---

## 6. Folklore vs documented fact

| Claim | Status |
|---|---|
| "Unlocking always drops Widevine to L3" | **[FOLK]** — common but vendor-dependent. Mechanism (TEE gating on boot state) is real; whether a given OEM arms it is not universal. |
| "Reflashing stock + relocking always restores L1" | **[FOLK], contradicted** — documented MT6789 Lenovo case where it did not. |
| "Widevine keys are in `persist`, you can back them up" | **[FOLK]** for Android 12+ TEE devices — true for some pre-2020 units only. mtkclient readback found no keybox. |
| "`persist` stores the Google account / FRP" | **[FOLK]** — that's AlephGSM's claim and it conflates `persist` with `frp`. `frp` holds FRP state. |
| "GSI breaks Widevine" | **[FOLK]** — with `/vendor` kept, the L1 path is intact; the unlock is the cause. |
| "OEM firmware package restores everything" | **False** — `nvdata`/`nvram` in OEM packages are blanked placeholders. |
| "TrickyStore/PIF restores Widevine L1" | **False** — different subsystem; they only touch attestation. |
| "Format All is fine as long as you reflash after" | **False** — documented permanent L1 loss. |
| "A GSI can pass DEVICE integrity if you relock" | **False** — DEVICE requires a *certified OEM image*; a GSI never is one. |
| "Play Integrity BASIC requires a locked bootloader" | **False** — BASIC explicitly permits unlocked/unverified. |

---

## 7. Source list

Documentation
- Play Integrity verdicts — https://developer.android.com/google/play/integrity/verdicts
- GSI requirements / no rollback — https://developer.android.com/topic/generic-system-image
- AOSP lock/unlock, `verifiedbootstate`, unlock wipes data — https://source.android.com/docs/core/architecture/bootloader/locking_unlocking
- AOSP Verified Boot / dm-verity — https://source.android.com/docs/security/features/verifiedboot/verified-boot
- AOSP AVB — https://source.android.com/docs/security/features/verifiedboot/avb
- AOSP RKP — https://source.android.com/docs/core/ota/modular-system/remote-key-provisioning
- Widevine keybox provisioning (OEM flow) — https://docs.nxp.com/bundle/UG10158/page/topics/provisioning_widevine_l1_keybox.html
- Widevine overview / Provisioning+Keybox+OEMCrypto are device-integration — https://developers.google.com/widevine/drm/overview
- Widevine L1/L2/L3 definitions — https://developer.bitmovin.com/playback/docs/widevine-security-levels-in-web-video-playback
- Netflix: HD requires L1; L3 = SD; modified OS can cause it — https://help.netflix.com/en/node/23939
- mtkclient usage (all commands) — https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md
- mtkclient V6 / patched bootrom note — https://github.com/bkerler/mtkclient
- SP Flash Tool secure-boot DA + Auth file — https://www.hovatek.com/forum/thread-439.html

Community reports
- L1 → L3 after Format All on MT6789 Lenovo, NOT restored by relock+stock — https://www.hovatek.com/forum/thread-47021.html
- MTK partition reference + sizes/offsets — https://gist.github.com/Azkali/64a8acbd25697dde50dd4999b0c063c0
- NV/IMEI loss mechanics, "OEM nvdata/nvram are blanked" — https://github.com/phhusson/treble_experimentations/issues/1012
- Keybox extraction, keys in TEE on A12+ — https://www.reddit.com/r/androidroot/comments/1us2hby/keyboxxml_extraction/
- SN Writer writes Wi-Fi/BT MAC, serial, DRMkey MCID — https://www.hovatek.com/forum/thread-12306.html
- MTK partition purposes (nvcfg/nvdata/nvram/protect1/protect2/proinfo) — https://alephgsm.com/2023/10/27/important-partitions-of-mediatek-mobile-phones/
- TrickyStore (keybox injection, closed-sourced) — https://github.com/5ec1cff/TrickyStore
- PIF fork (original repo removed) — https://github.com/KOWX712/PlayIntegrityFix
- Format All permanently loses Widevine L1 (MTK tablet) — https://github.com/omixmobile/firmware
