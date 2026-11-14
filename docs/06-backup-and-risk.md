# What you lose, what you can back up, and what to do first

This is the document to read before doing anything irreversible.

---

## The one-paragraph answer to "will I lose Netflix HD / Widevine L3?"

**Almost certainly not because of the GSI — because of the unlock.** On this tablet the entire
Widevine L1 path lives in `/vendor` and the Trustonic TEE, and a system-only GSI swap never
touches either:

```
MediaDrm (GSI /system)
  → android.hardware.drm@1.4-service.widevine     /vendor/bin/hw      (kept)
    → liboemcrypto.so                             /vendor/lib64       (kept)
      → Trustonic TEE (tbase)                     tee_a               (kept)
        → keybox in secure storage                not a file you can copy
```

What *does* break it is unlocking the bootloader, because TEEs commonly refuse secure-world
services once `ro.boot.verifiedbootstate` is `orange` and `ro.boot.flash.locked` is `0`. Some
vendor TEEs still serve L1 while unlocked; some do not. Ours is Trustonic (`libtlcWidevineModularDrm.so`,
`liburee_meta_drmkeyinstall.so`), and we have no data on its policy for this exact unit.

The closest documented analogue is the same SoC family — a **Lenovo Tab P11 2nd Gen
(TB350XU, MT6789/G99)** where a user flashed with SP Flash Tool, restored IMEI and serial
successfully, and still found **L1 → L3, Prime Video stuck at SD**. Relocking, unrooting and
reflashing **stock** did not bring L1 back
(<https://www.hovatek.com/forum/thread-47021.html>). Treat that as the pessimistic case.

Netflix's own support page states it plainly: HD requires Widevine L1, L3 means SD, and
*"This can happen if your device is running a modified version of the Android operating
system"* (<https://help.netflix.com/en/node/23939>).

### Can you back up the key? Honestly: no — but dump anyway

The Widevine keybox is provisioned at manufacture into **secure storage**, not a readable
partition. On Provision 4.0 / RKP devices (AOSP since Android 12) the private keys are
generated in secure hardware and never leave it
(<https://source.android.com/docs/core/ota/modular-system/remote-key-provisioning>). A
researcher dumping `persist`, `protect1` and `protect2` on a comparable MTK device found **no
keybox** — the keys were in the TEE.

So what you can do is a **lottery ticket, not insurance**: dump every partition that might
hold an encrypted provisioning blob (`persist`, `protect1`, `protect2`, `nvdata`, `nvram`,
`nvcfg`, `sec1`) bit-exactly, and if L1 drops, try restoring them **on the same unit** before
reflashing anything. That has worked for some and failed for others.

**The critical ordering rule:** those partitions are only readable with root, and root
requires the unlock that may destroy the state. Break the loop by dumping with **mtkclient in
preloader mode before you touch `seccfg`**. Do not unlock first "so I can `adb root` and then
back up" — that is exactly backwards.

---

## 1. Play Integrity / attestation

| Verdict | What it needs | After unlock | After GSI |
|---|---|---|---|
| `MEETS_BASIC_INTEGRITY` | software-ish checks | usually **survives** (explicitly allowed for unlocked bootloaders) | survives |
| `MEETS_DEVICE_INTEGRITY` | verified boot state + CTS-approved build | **fails** | fails |
| `MEETS_STRONG_INTEGRITY` | hardware-backed key attestation, locked bootloader | **fails** | fails |

Practical consequences: Google Wallet / tap-to-pay stops working, most banking apps refuse to
launch, some games with anti-cheat block, and Play Protect may nag. Surviving is the exception,
not the rule.

Two details worth being precise about, because they change what "recovery" means:

- `DEVICE` requires *"hardware-backed proof that the device bootloader is locked and the
  loaded Android OS is a certified device manufacturer image"*. An unlocked bootloader fails
  it, **and a GSI fails it even if you later relock** — a GSI is by definition not a certified
  OEM image. So `DEVICE`/`STRONG` are gone for as long as you run a GSI, relocked or not.
- They come back only after **stock firmware + relock**. That is the honest recovery path.

Mitigations exist (Play Integrity Fix, TrickyStore, keybox injection). They are an arms race,
they violate the Play/ToS terms of the apps involved, and they routinely break after Google
updates. This document does not recommend them for a device you rely on. None of them restore
Widevine — they are an attestation workaround, not a DRM fix.

### If you ever relock: do not do it on a modified device

`fastboot flashing lock` on a device whose `system`/`vbmeta` are not stock will brick it into a
bootloop that only SP Flash Tool can fix. Worse, there is an **AVB rollback trap**: relocking
with an *older* OEM package than the one already on the device can trip the rollback index and
leave the device refusing to boot. If you relock, do it from a fully stock state flashed with
the same (or newer) firmware build that was on the device — and dump `seccfg` first so you know
what lock state you started from.

---

## 2. The MediaTek partitions that are per-unit and irreplaceable

Sizes below are from this device's scatter file (verified against the GPT; see
`appendix-a-partition-map.md`).

| Partition | Size | Contains | If lost |
|---|---|---|---|
| `persist` | 55,264 KiB | Sensor calibration (`sns.reg`: accel/ALS/prox), touch & pen calibration, Wi-Fi/BT cal data, misc factory files | Auto-rotate, auto-brightness, proximity, touch/pen accuracy wrong or dead. **Nothing regenerates it.** |
| `nvdata` | 64 MiB | AP-side NV: runtime Wi-Fi/BT config, MAC-adjacent data, feature flags | "nvdata corrupted"; Wi-Fi/BT may fail to initialise; MAC unstable |
| `nvram` | 64 MiB | MTK NVRAM: RF calibration, **Wi-Fi MAC, BT MAC** | Dead or wrong-MAC Wi-Fi/BT |
| `nvcfg` | 32 MiB | NV config template used to rebuild NV | NV rebuild failures |
| `proinfo` | 3 MiB | Product info: model, region, **serial number**, sometimes Wi-Fi MAC | Serial becomes `0000000`, wrong region/model |
| `protect1` | 8 MiB | Protected NV / carrier-radio data | NV corruption |
| `protect2` | 8 MiB | Protected secure storage (`/mnt/vendor/protect_s`), TEE-adjacent | NV + possible secure-storage problems |
| `seccfg` | 8 MiB | **Bootloader lock state + dm-verity state**, cryptographically tamper-protected | Stuck unlocked, or won't boot, or won't relock |
| `otp` | 43 MiB | One-time-programmable factory area | Nothing — **dump for the record, never restore** |
| `expdb` | 128 MiB | Exception/crash database | Crash history only; regenerated |
| `frp` | 1 MiB | Factory Reset Protection state | Only matters if a flash leaves FRP odd; restoring it *clears* FRP (security-relevant) |
| `boot_para` | 1 MiB | Boot-mode args LK → kernel | Usually benign, regenerated |
| `sec1` | 2 MiB | Secondary security data / efuse shadow | Unknown; cheap to dump |
| `dram_para` | 25 MiB | DRAM timing calibration | Possible no-boot / instability |
| `preloader` | boot partition | First-stage bootloader | Hard-brick territory. Dump **both** boot regions — boot2 holds the serial number. |
| `flashinfo` | 16 MiB | Storage bad-block / wear metadata, sentinel last partition | **Never write to it** |

**The OEM firmware package does not contain any of these.** Its `nvdata`/`nvram` images (where
present at all) are blanked placeholders. There is no copy anywhere except your own dump.

### Priority order if you only dump some

1. `persist` — irreplaceable, and its loss is immediately visible (sensors, touch)
2. `nvram` + `nvdata` + `proinfo` — Wi-Fi/BT MAC and serial identity
3. `seccfg` — so you can reason about lock state, and get back if a relock goes wrong
4. `super` — the stock system, so you can go back without a 5 GB reflash
5. everything else

---

## 3. Other things you actually lose

These live in `/system` or `/system_ext`, so **preserving `/vendor` does not save them**:

- **OEM preinstalled apps.** On this device the entire footprint is one package,
  `cn.com.techvision.sound` (an audio-tuning utility). Nearly nothing to lose — a genuinely
  favourable quirk of this tablet.
- **Google apps, unless you pick a GMS GSI.** The stock build has 210 packages, 85 of them
  Google (`com.google.android.gms`, `com.android.vending`, Play Store). A pure `aosp_arm64`
  GSI has **no Play Store at all**. See `05-image-options.md`.
- **OEM camera features** (AI modes, wide-angle processing) if they were implemented in the
  system-side camera app rather than the vendor ISP tuning.
- **Stylus features.** The T3 is sold with an optional WGP-protocol active pen. Any
  system-side pen UX (palm rejection presets, shortcuts) is gone; the pen should still work as
  a digitiser because that is vendor-side.
- **Face unlock**, if implemented system-side.
- **Navigation-bar / gesture defaults and rounded-corner config.**
- **Official OTA updates.** `update_engine` payloads are keyed to the stock system hash, so
  they will never apply again. You are frozen at whatever GSI you install.

What you **keep**, because it is vendor-side: the kernel and its modules, all hardware HALs,
Wi-Fi/BT/GNSS firmware, audio tuning, display calibration, camera IQ tuning, the Trustonic
TEE, and the DRM HAL stack.

---

## 4. Deciding whether it is worth it

A blunt cost/benefit, for this specific tablet:

| | Stock Android 13 (SPL 2024-09-05) | Modern GSI |
|---|---|---|
| Security patches | frozen, ~2 years stale | current |
| Android version | 13 | 14 / 15 / 16 |
| Play Store | yes | yes, if you pick a GMS or LineageOS GSI |
| Netflix HD | yes (L1) | **gamble** — likely SD if the unlock closes the TEE |
| Banking / Wallet | yes | **no** (unless you fight Play Integrity) |
| OTA updates | dead | dead (but you can re-flash a new GSI) |
| Sensors / camera / audio | full | should be full (vendor-side) |
| Risk of brick | — | low (SP Flash Tool recovery) |

If this tablet is a media/kiosk/second-screen device and you do not need banking or Netflix
HD, a GSI is a clear win. If you need tap-to-pay or HD streaming on it, **the unlock is the
cost, and it may not be refundable**.
