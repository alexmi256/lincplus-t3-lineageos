# Handoff: building an updated LineageOS 22.2 GSI

Status: planning document. Nothing in here has been executed yet.
Written 2026-11-13. Supersedes nothing; complements `10-widevine-l1-on-gsi.md` and
`11-android15plus-outlook.md`.

## 1. Purpose

Record what exists today, and define the experiment: **build LineageOS 22.2 (Android 15) as a GSI
ourselves**, first reproducing the last known-good artefact, then folding in updates.

The motivating gap: Andy Yan's 22.2 GSI is frozen at **2025-06-21**, while his Android 14 line is
still rebuilt monthly. Our tablet currently runs a **2026-11-09 A14 build with security patch level
2026-11-01**. A stock 22.2 GSI would therefore be a *security downgrade* by ~17 months. Building it
ourselves is the only way to get Android 15 *and* current patches.

## 2. Where the project stands

| Item | State |
|---|---|
| Tablet `SERIAL-TEST` | LineageOS 21 (Android 14), bootloader unlocked (orange), **Widevine L1** |
| Running build | `lineage_arm64_bgN-userdebug 14 UQ1A.240205.004 eng.crossg.20261109.110617` |
| Security patch | `2026-11-01` (vendor-patched via monthly rebuild) |
| Brand prop | `Lincplus` — identity patch active (this is what holds L1) |
| Tablet `SERIAL-DAILY` | **Stock Android 13, locked. Never flash this one.** |
| Rollback A (fast) | `build/super-stockid.img` — the working A14+L1 image |
| Rollback B (full) | `backup/readback-SERIAL-TEST/` + `FW/` OEM package via SP Flash Tool on the Windows box |
| Flashing host | this machine (24 threads, 15 GB RAM, 1.7 TB free) via `lincplus-android-tools:5` |
| Build host | **not yet provisioned** — needs ≥64 GB RAM (see §5) |

### Image inventory in `build/`

| File | What it is | Keep? |
|---|---|---|
| `super-stockid.img` | A14 GSI + identity patch. **The working image.** | **yes** |
| `lineage-21-arm64_bgN.img` | A14 GSI system image, unpatched | yes (source) |
| `lineage-stockid.img` | intermediate patched A14 system image | optional |
| `super-new.img` | first A14 build, unpatched identity → L3 | delete |
| `super-aosp14.img` | Google AOSP 14 GSI, `user` build, no Play, no root | delete |
| `super-gms14.img` | Google GMS 14 GSI — **bootloops on this vendor** | delete |
| `vbmeta-flags3.img` | 8,192 B, `Flags: 3` — required to boot any modified `super` | **yes** |
| `patch-gsi-identity.sh` | reusable identity patcher | **yes** |
| `make-super.sh` | assembles `super` from a system image + OEM partitions | **yes** |

## 3. What "updated 22.2" can mean — pick one per phase

| Target | Work | Value |
|---|---|---|
| **A. Reproduce** the 2025-06-21 22.2 image | full source build, no code changes | proves the toolchain works end to end; gives a baseline to diff |
| **B. Security-bump** it | rebuild against current `lineage-22.2` HEAD, which still receives monthly bulletins | Android 15 **and** patch parity with what we run now |
| **C. Feature upgrade** | move 22.2 → 23.x / 24.0 | **not viable** — vendor API level 31 blocks Android 16+ (§4 of `11-android15plus-outlook.md`) |

Recommended order: **A, then B.** A is the "what does it take" measurement; B is the actual goal.

## 4. The build system — verified branch names

Andy Yan's "Light" GSI is three repos plus the LineageOS tree. Branch names confirmed via the GitHub
API on 2026-11-13:

| Component | Repo | Branch |
|---|---|---|
| Manifest / source | `LineageOS/android` (official!) | **`lineage-22.2`** |
| Build driver | `AndyCGYan/lineage_build_unified` | **`lineage-22-light`** |
| Patch set | `AndyCGYan/lineage_patches_unified` | **`lineage-22-light`** |
| Device tree | `AndyCGYan/android_device_lineage_gsi` | **`lineage-22`** |

Note the asymmetry: for **Android 14** he forked the manifest (`LOS21-pre-QPR2/android`, pinned
pre-QPR2), but for **Android 15 he uses the official LineageOS manifest directly**. There is no
`LOS22*` fork org (both candidate names return 404).

Authoritative commands, from `lineage-22-light/README.md`:

```bash
mkdir lineage-22-build-gsi && cd lineage-22-build-gsi
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs

git clone https://github.com/AndyCGYan/lineage_build_unified  lineage_build_unified  -b lineage-22-light
git clone https://github.com/AndyCGYan/lineage_patches_unified lineage_patches_unified -b lineage-22-light

bash lineage_build_unified/build_unified.sh treble 64VN 64GN
```

`64VN`/`64GN` = arm64 vanilla / GApps. Those suffixes are the `vN`/`gN` in his filenames. The device
tree is pulled in by the script's local manifests, not cloned by hand — but keep
`android_device_lineage_gsi` on `lineage-22` in mind when debugging build failures, since that is
where GSI-specific fixes (sysbta Bluetooth-audio HAL, resetprop, sepolicy) live.

## 5. Hardware sizing — this is the gating constraint

LineageOS' own wiki, for a normal device build:

> RAM: "16 GB to build up to `lineage-17.1`, 32 GB or more for `lineage-18.1`, and **64 GB for
> `lineage-21` and up**"
> Storage: "**400 GB for `lineage-21` and up**", more with `ccache`

So for 22.2: **≥64 GB RAM, ≥400 GB SSD, ideally 1 TB, 16–32 threads.** The current host has 24
threads and 1.7 TB free — fine for storage, **15 GB of RAM is nowhere near enough**. ZRAM helps but
does not close a 4× gap. That is why the build moves to the new machine.

Practical notes for tomorrow's box:
- Use an **SSD/NVMe**, not spinning rust. Build time is I/O bound as much as CPU bound.
- Leave headroom: the tree plus `out/` plus `ccache` (default 50 GB, often 100 GB) grows fast.
- Enable `ccache` early; it makes iteration on the patch set 3–5× faster after the first build.
- First full build realistically **3–8 hours** on 16 threads; subsequent incremental builds are much
  faster.

## 6. Phase 0 — environment prep (new machine)

### The build host, as provisioned (2026-11-13)

| | |
|---|---|
| Host | `build-host` — **BUILD-HOST-IP** |
| Login | `user` (password auth over SSH); **root via `sudo`** — direct `root@` SSH is refused |
| OS | Ubuntu **26.04.1 LTS**, kernel 7.0.0-43-generic |
| CPU | AMD Ryzen 9 **5900X**, 12 cores / 24 threads |
| RAM | **62 GiB** + 8 GiB swapfile (no zram) |
| Disk | 915 GB NVMe, **606 GB free** (`/`) |
| Hermes gateway | installed and running (`gateway run`, uid 1000) — usable as an alternate control path |

Verdict against §5: RAM is ~3 % under the 64 GB figure but with swap it is at spec; disk clears the
400 GB bar with room for one tree plus ccache, **not** two full trees. Plan to keep a single tree and
archive `out/` artefacts if both are needed.

### Provisioned state (2026-11-14, overnight)

| Item | State |
|---|---|
| Docker access | `user` added to the `docker` group — no `sudo` needed (fresh SSH session required) |
| Build image | `los22-builder:latest`, 1.06 GB, `ubuntu:24.04` + AOSP host deps + `git-lfs`/`ccache`/`erofs-utils` |
| Tree | `~/build/src` — `repo init -b lineage-22.2 --git-lfs` + full `repo sync` |
| GSI repos | `lineage_build_unified` @ `lineage-22-light`, `lineage_patches_unified` @ `lineage-22-light`, `android_device_lineage_gsi` @ `lineage-22` |
| ccache | `~/build/ccache`, limit 100 GB |
| Output | `~/build/home/build-output/` (container `$HOME=building`); logs in `~/build/logs/` |
| Automation | systemd **user** unit `los22-orchestrator` — waits for the sync container to exit 0, then starts the build unattended |

**Deliberate deviation from §7:** the tree was synced at **current `lineage-22.2` HEAD**, not pinned to
2025-06-21. Rationale: HEAD is what Phase 2 actually needs, and pinning first would cost a second full
sync. Phase 1 "reproduce the frozen build" remains possible later via
`repo init -m default.xml <rev-before-2025-06-21>` + `repo sync`, at the cost of a re-sync.

**Rootless Docker caveat:** this host's daemon is rootless, so container uid 0 == host `user` while
container uid 1000 maps to a subuid. Do **not** pass `-u $(id -u):$(id -g)` — it cannot write the bind
mounts. See `13-docker-build-env-research.md` Addendum 3.


**22 build packages were missing** at provisioning, plus `repo` and any JDK — but this is now moot:
nothing is installed on the host. The container supplies the toolchain and the tree supplies clang,
JDK and ninja via `prebuilts/`. The host-side `apt` step in this section is retained only as a
fallback if a bare-metal build is ever wanted.



```bash
# Ubuntu 26.04 host — libxml2-16 replaces libxml2 here
sudo apt install bc bison build-essential ccache curl erofs-utils flex g++-multilib \
  gcc-multilib git git-lfs gnupg gperf imagemagick kmod protobuf-compiler python3-protobuf \
  lib32readline-dev lib32z1-dev libdw-dev libelf-dev libgnutls28-dev lz4 libsdl1.2-dev \
  libssl-dev libxml2-16 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools \
  xsltproc xxd zip zlib1g-dev openjdk-21-jdk
```

Caveats from the wiki: on **Ubuntu 26.04+** swap `libxml2` for `libxml2-16`. The JDK is normally
supplied by AOSP prebuilts, so a system JDK is only for convenience.

Then:
```bash
mkdir -p ~/bin && curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo \
  && chmod a+x ~/bin/repo && export PATH=~/bin:$PATH
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
export USE_CCACHE=1 && ccache -M 100G
```

## 7. Phase 1 — reproduce the frozen 22.2 (the measurement)

Goal: build the **2025-06-21** state, not today's HEAD, so "it works" is a clean baseline.

Approach: `repo init` at `lineage-22.2`, then **pin the manifest** to a revision near 2025-06-21
before syncing —

```bash
cd .repo/manifests
git log --before=2025-06-21 -1 --format=%H   # choose the last manifest commit before the freeze
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs \
  -m default.xml <pinned-revision>           # or check out the manifest tree at that commit
repo sync -c -j$(nproc) --force-sync --no-clone-bundle --no-tags
```

Then clone the two Andy repos at `lineage-22-light`, run `build_unified.sh treble 64GN`, and record:

- [ ] build completes, no patch application failures (`apply_patches.sh` output)
- [ ] output `system.img` size within a sane range (~2.5–3.2 GB; A14 was 3.20 GB)
- [ ] reported `ro.build.version.security_patch` (should be ~2025-06)
- [ ] wall-clock and peak RAM for the build — **this is the number that sizes Phase 2**

If patches fail to apply against a pinned tree, that is itself the finding: the `lineage-22-light`
patch set is tuned to a specific point in the branch, and drift is the main risk in Phase 2.

## 8. Phase 2 — applying updates

Two strategies, in order of preference:

**B1 — rebuild against current `lineage-22.2` HEAD (recommended).**
LineageOS still merges full monthly security bulletins into 22.2 for as long as Google ships A15
bulletins (see `11-android15plus-outlook.md` §3). So simply syncing today's `lineage-22.2` and
rebuilding should produce an image **newer than 20250621** with no cherry-picking. Risk: the
`lineage-22-light` patch set may no longer apply cleanly to drifted code.

**B2 — cherry-pick specific fixes onto the pinned tree.**
Only if B1's patch application fails. Pull the relevant AOSP security commits
(`android-15.0.0_rXX` tags) from `platform_frameworks_base`, `platform_system_*`, etc., via Gerrit.

In both cases, when the build reports a security patch level, **confirm the claim**: check that the
patches you intended are actually in the tree before trusting the date string. Bumping
`ro.build.version.security_patch` without the corresponding commits is a lie the build will happily
tell, and it is the single easiest mistake to make in this phase.

Sanity check to run after any rebuild:
```bash
grep -h 'security_patch' $OUT/system/build.prop        # must match the merged bulletin
```

## 9. Phase 3 — turning the build into a flashable tablet image

The build produces a system image; the tablet needs a `super` with OEM vendor/product. This is the
pipeline already proven four times:

```bash
# 1. identity patch — WITHOUT THIS THE GSI DROPS TO WIDEVINE L3
build/patch-gsi-identity.sh <system.img>            # defaults: Lincplus / T3_US / TP1A... / 20241016
#    it rewrites /system/build.prop, /system/product/etc/build.prop,
#    /system/system_ext/etc/build.prop via debugfs (all three, or the product overlay wins)

# 2. assemble super around the OEM partitions
build/make-super.sh <patched-system.img>            # -> build/super-<name>.img

# 3. flash: super + vbmeta-flags3 + WIPE (non-negotiable)
fastboot flash super build/super-<name>.img
fastboot flash vbmeta build/vbmeta-flags3.img
fastboot erase userdata && fastboot erase metadata && fastboot format userdata
```

`patch-gsi-identity.sh` reads release/type from the image it is given, so it adapts to Android 15
automatically — **but re-check the prop layout** (§11) rather than assuming the three paths are still
the only overlays.

## 10. Verification checklist (every flash)

- [ ] boots to home screen, `adb devices` shows `device`
- [ ] `getprop ro.build.version.release` → `15`
- [ ] `getprop ro.product.brand` → `Lincplus` (identity patch applied)
- [ ] `getprop ro.boot.verifiedbootstate` → `orange`, `ro.boot.flash.locked` → `0`
- [ ] vendor HAL alive: `adb shell ps -A | grep widevine` shows `drm@1.x-service.widevine`
- [ ] **DRM Info app → Security Level L1, System ID `29739`, Max HDCP 2.3, 50 sessions** (screenshot it)
- [ ] `ro.vendor.api_level` still `31` (unchanged — it comes from vendor, not system)

L3 instead of L1 means the identity patch did not land; that is the first thing to check, not the
vendor partition.

## 11. Pitfalls we already paid for — do not rediscover these

1. **Always wipe userdata when changing `super` contents.** Skipping it produced a bootloop once.
   The wipe also costs an adb re-authorisation round trip — accept it.
2. **Patch all three identity overlays.** `ro.product.system.*` alone is overridden by
   `/system/product/etc/build.prop`; the first attempt silently stayed at L3 because of exactly this.
3. **Use `debugfs`, not a loop mount.** Android system images are ext4 with `shared_blocks` and ~100 %
   full; `mount -o rw` fails and `e2fsck -E unshare_blocks` does not help.
4. **`vbmeta` needs `Flags: 3`** (verification + verification-error disabled) or the device will not
   boot a modified `super`.
5. **`lpdump` extents are in 512-byte units on this device, not 4096.** Verify every size against a
   real extracted file before feeding it to `lpmake`.
6. **`super` geometry is fixed**: 9,663,676,416 bytes total, metadata 10.2, 3 slots,
   `virtual_ab_device` flag. A system image above ~3.2 GB will not fit alongside OEM `product`.
7. **Never flash unit `SERIAL-DAILY`.** Its `persist`/`nvram` differ; cross-restoring readbacks is
   unrecoverable.
8. **`fastboot flashing unlock` can return OKAY while staying locked** — the on-screen Volume Up
   prompt must be confirmed within ~20 s. Retry until `unlocked: yes`.
9. **Google GSIs are `user` builds** → no `adb root`, and `boot-debug.img` on top caused a bootloop.
   LineageOS `userdebug` is what makes the DRM Info PairIP workaround possible; keep that property.
10. **`lpunpack` returns the full partition with zero padding** — compare only the first N bytes when
    verifying an image round-trip.

## 12. Estimated cost

| Phase | Work | Time |
|---|---|---|
| 0 | env prep + `repo sync` (~100 GB) | 1–3 h (network bound) |
| 1 | reproduce 2025-06 frozen 22.2 | 3–8 h build, + debugging |
| 2 | resync to HEAD, re-apply patches, rebuild | 1–3 h (ccache warm) |
| 3 | identity patch, `super`, flash, verify | 30–45 min |

## 13. Open questions for the build host

1. Disk: 1 TB NVMe or 400 GB? `ccache` + two build trees make 400 GB tight.
2. Keep Phase 1's tree around for diffing, or reclaim space and only keep `out/` artefacts?
3. Do we want to **sign** the build (`sign_target_files.sh`)? Not strictly required — AVB is disabled
   by `vbmeta-flags3` — but signed images are what we compare against Andy's `-signed` artefact.
4. If B1 fails due to patch drift, do we pin to an intermediate manifest date (e.g. late 2025) as a
   compromise before resorting to cherry-picks?

## 14. Quick reference

```bash
# tablet
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.product.brand

# build host
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
repo sync -c -j$(nproc) --force-sync --no-clone-bundle --no-tags
bash lineage_build_unified/build_unified.sh treble 64GN     # GN = GApps; VN = vanilla

# artefacts
$OUT/system.img            # the GSI system image
$OUT/*.zip                 # flashable package (not used by our path)
```

Reference documents: `10-widevine-l1-on-gsi.md` (why the identity patch exists),
`11-android15plus-outlook.md` (version ceiling and support policy), `09-windows-vm-brief.md`
(SP Flash Tool rollback), `appendix-a-partition-map.md`.
