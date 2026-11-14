# Findings log — issues hit and how they were resolved

Chronological working notes. Every entry is something that actually went wrong or was
genuinely surprising during this research; the point is that the next person does not have
to rediscover it.

---

## F1 — Debian's `fastboot` is too old to do anything useful

**Symptom.** `fastboot --version` → `fastboot version 29.0.6-debian` (2019).
`fastboot reboot fastboot` and `flash system` against a dynamic partition fail or are
silently ignored.

**Cause.** Debian bookworm ships `android-sdk-platform-tools` at a snapshot from before
`fastbootd` and logical-partition support landed.

**Resolution.** Install Google's current platform-tools and shadow the Debian binaries:

```dockerfile
RUN curl -fsSLo /tmp/pt.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip \
 && unzip -q /tmp/pt.zip -d /opt \
 && ln -sf /opt/platform-tools/adb /usr/local/bin/adb \
 && ln -sf /opt/platform-tools/fastboot /usr/local/bin/fastboot
```

Now `fastboot version 37.0.1` and `fastbootd`, `is-logical:*`,
`resize-logical-partition` all work.

---

## F2 — `apt-get install android-libsparse-utils` does not exist

**Symptom.** Image build fails: `E: Unable to locate package android-libsparse-utils`.

**Resolution.** The correct Debian package is **`android-sdk-libsparse-utils`** (provides
`img2simg` / `simg2img`). Debian has `android-libsparse` (the library) and
`android-sdk-libsparse-utils` (the tools), but not `android-libsparse-utils`.

---

## F3 — `lpdump` is not packaged anywhere on Debian

**Symptom.** No `lpdump`, `lpunpack`, `lpmake` in any Debian repo. Can't inspect the
`super` partition layout.

**Resolution, part 1.** Wrote `work/tools/lpdump.py`, a dependency-free liblp metadata
parser. Getting it right took three attempts, each a real trap:

1. **Wrong magic.** I used `0x616c4467` (`LP_METADATA_GEOMETRY_MAGIC`, `"gDla"`). The
   *header* magic is `0x414C5030` (`"0PLA"`, `LP_METADATA_HEADER_MAGIC`).
2. **Wrong header layout.** I assumed 32-bit `header_checksum` / `tables_size` /
   `tables_checksum`. In fact `header_checksum` and `tables_checksum` are **SHA-256 (32
   bytes each)**, which pushes `tables_size` to offset 44 and the first table descriptor to
   offset **80**. The header is 256 bytes: `flags` at 128, `reserved[124]` after it.
3. **Wrong table base.** Descriptor `offset` values are relative to the **tables area**
   (`metadata_start + header_size`), not to the metadata start.

**Resolution, part 2.** Built the real tools from source
(`LonelyFool/lpunpack_and_lpmake`, fully vendored: zlib, protobuf, boringssl, liblp):

```dockerfile
RUN apt-get install -y clang lld make zlib1g-dev && \
    git clone --depth 1 https://github.com/LonelyFool/lpunpack_and_lpmake /opt/lp && \
    cd /opt/lp && bash make.sh && cp bin/* /usr/local/bin/
```

**Validation.** The Python parser now agrees with the real `lpdump` on every partition,
extent and size — including catching `Header flags: virtual_ab_device`, which the Python
parser reports as `flags=0x1`. That flag is the only reliable way to tell this device is
**Virtual** A/B rather than legacy A/B from the super metadata alone.

---

## F4 — `zlib.h` missing when building `lpmake`

**Symptom.** `libsparse/output_file.cpp:31:10: fatal error: 'zlib.h' file not found`.

**Resolution.** Add `zlib1g-dev`. The repo vendors *zlib sources* for its static build but
still `#include <zlib.h>` from the system.

---

## F5 — Google's own documentation points at a file that no longer exists

**Symptom.** The official GSI compatibility check says:

```bash
adb shell cat /system/etc/ld.config.version_identifier.txt | grep -A 20 "\[vendor\]"
```

On this device: `No such file or directory`. And `ls /system/etc/ld.config*` — nothing.

**Resolution.** On Android 13 the linker config lives at **`/linkerconfig/ld.config.txt`**,
and `/linkerconfig` has mode 0700 root, so `cat` fails with `Permission denied`. Use `grep`
(the shell runs as `shell`, which can traverse but not read arbitrary files):

```bash
adb shell 'grep -A 30 "^\[vendor\]" /linkerconfig/ld.config.txt' | grep isolated
# namespace.default.isolated = true
```

Worth correcting upstream in any guide that copies Google's snippet, because the failure mode
is "file not found", which reads like "your device is not compliant" rather than "the path
moved".

---

## F6 — Android's boot image sections are page-aligned, not packed

**Symptom.** Extracting the `boot.img` ramdisk at `4096 + kernel_size` produced zeros.

**Cause.** MTK pads each section to the 4096-byte page. `kernel_size` from the v4 header is
19,586,404 but the ramdisk actually starts at `0x12af000` — 668 bytes further along.

**Resolution.** Find the section by scanning for a decompressor magic rather than trusting
arithmetic:

```bash
grep -abo $'\x02\x21\x4c\x18' boot.img   # LZ4 legacy
grep -abo $'\x1f\x8b\x08'      boot.img   # gzip
```

The ramdisk is **LZ4 legacy** (`0x02214c18`), not gzip — worth knowing, because `gzip -dc`
silently produces nothing and looks like a corrupt image.

---

## F7 — AVB vbmeta images have **no** header checksum, and I corrupted one finding out

**Symptom.** My first `avb_flags.py` assumed AVB had a 32-byte `header_checksum` field (the
32 bytes at offset 12 looked exactly like a SHA-256). Patching it produced an image that
`avbtool info_image` rejected with `OSError: [Errno 22] Invalid argument`, and my own parser
reported nonsense (`auth_block_size = 137438953472`).

**Cause / truth.** AVB v1.0's `AvbVBMetaImageHeader` has **no checksum field**:

```
!4s2L   magic, major, minor
2Q      auth_block_size, auxiliary_block_size
L       algorithm_type
2Q×5    hash / signature / public key / pk metadata / descriptors (offset, size)
Q       rollback_index
L       flags                     <-- offset 120, what we actually want
L       rollback_index_location
47sx    release_string
80x     reserved                  -> 256 bytes total
```

The RSA signature covers header + auxiliary block; that is the integrity mechanism.

**Resolution.** `work/tools/avb_flags.py` now parses the header with avbtool's exact
`FORMAT_STRING` and patches only the 4 bytes at offset 120. Verified:

```
Flags: 3
Public key (sha1): cdbb77177f731920bbe0a0f94f84d9038ae0617d
Descriptors: Chain Partition descriptor: boot, vbmeta_system, vbmeta_vendor
```

Chain descriptors survive, which is the whole point: flashing Google's generic 512-byte
`vbmeta.img` would have discarded them.

**Lesson.** `avbtool info_image` is an excellent validator — it refuses malformed headers and
prints the flags. Always round-trip through it.

---

## F8 — `adb pull` into a host path writes to the *container's* path

**Symptom.** `adb pull /system/etc/security/otacerts.zip devdump/` → `cannot create file/
directory: No such file or directory`, even though `devdump/` existed on the host.

**Cause.** `adb` runs inside the `rea-agent-ghidra` container, whose filesystem is not the
host's. Relative paths resolve against the container's cwd.

**Resolution.** Stream it out instead:

```bash
docker exec rea-agent-ghidra adb exec-out cat /system/etc/security/otacerts.zip > devdump/otacerts.zip
```

---

## F9 — The OEM-unlock toggle does not exist, but unlocking is allowed anyway

**Symptom.** Two apparently contradictory readings:

- `settings get global oem_unlock_allowed` → `null` (the Developer-options toggle that
  normally writes this setting is absent)
- `getprop sys.oem_unlock_allowed` → `1`
- `fastboot flashing get_unlock_ability` → `unlock_ability is true`

**Interpretation.** The persistent unlock permission is not driven by the userspace setting
here; it is baked in at the factory (or the toggle was removed from Settings). The value that
matters — the one LK checks — says **unlock is permitted**.

**Resolution.** No action needed. Verified by querying the bootloader directly rather than
trusting the Settings app. The LK binary also contains the full flow, including the on-screen
`Unlock bootloader? Yes (Volume UP or Volume Down)` confirmation.

**Lesson.** On MTK, ask the bootloader, not the UI.

---

## F10 — `vbmeta_system` signs **both** `system` and `product`

**Symptom.** Initially assumed `vbmeta_system` only covered `system`, so dropping a GSI into
`system_a` would only invalidate one hashtree.

**Truth.** `avbtool info_image --image vbmeta_system.img` lists hashtree descriptors for
**`product`** *and* **`system`**, with the same salt. Both roots are in that one image.

**Consequence.** You need exactly one vbmeta patch (the top-level one) — but you must not
then try to "repair" `vbmeta_system` by flashing Google's empty vbmeta over it, or you lose
the chain.

---

## F11 — `fastboot getvar is-logical:system` fails; the partition is `system_a`

**Symptom.** `getvar:is-logical:system → FAILED (remote: 'Partition not found')`.

**Cause.** Logical partition names carry the slot suffix. `system_a` works:
`is-logical:system_a: yes`. `fastboot flash system ...` still works because fastboot appends
the active slot automatically.

---

## F12 — `partition-type:system_a` fails with "Fastboot HAL not found" ⚠️ OPEN

**Symptom.** In `fastbootd`:

```
$ fastboot getvar partition-type:system_a
FAILED (remote: 'Fastboot HAL not found')
```

**Cause.** Android 11+ `fastbootd` implements some `getvar`s through the AIDL
`android.hardware.fastboot.IFastboot` HAL, which supplies partition type/name resolution.
The generic Google GSI ramdisk that this device uses as its `boot.img` does not ship that
HAL, and MTK's `vendor_boot` does not provide it either.

**Impact — unresolved.** `getvar:partition-size` and `is-logical` work (they come from
`fs_mgr`), and `flash`/`resize-logical-partition` are implemented in `fastbootd` itself, so
the actual flashing sequence *should* be unaffected. But this is the one place where a
command we want is missing, and it is worth confirming with a harmless test
(`fastboot flash` to a scratch logical partition, or simply watching whether
`fastboot flash system` reports a HAL error) **before** committing to the permanent flash.

**Tracked as:** the first thing to check in the flashing phase.

---

## F13 — `cpio` extraction produced unreadable files

**Symptom.** After extracting the 22 MB `vendor_boot` vendor ramdisk, `grep fstab.mt8781`
→ `Permission denied`, even as root in the container.

**Cause.** The cpio payload carries Android's ownership/mode bits (e.g. 0640 root:root with
unusual supplementary groups), and some entries extract with modes the container's UID cannot
traverse.

**Resolution.** `chmod -R u+rwX .` after extraction, or just read the same file from the
running device at `/vendor/etc/fstab.mt8781` — which is what I did, and confirmed both copies
are byte-identical.

---

## F14 — The `avb_keys=` line in the fstab looks like a GSI free pass but is inert

**Observation.** `fstab.mt8781` carries:

```
avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
```

which *looks* like the device will accept a Google GSI signature. Two checks:

1. Only Q/R/S (Android 10/11/12) keys are listed — no `t-gsi` (13) or later.
2. The key files **do not exist**: no `/avb` in the `boot.img` ramdisk, no `/avb` in the
   22 MB `vendor_boot` vendor ramdisk, and `ls /avb` on the running system → no such
   directory.

**Conclusion.** Vestigial BSP configuration. Do not plan around it. (It is still useful
evidence that the BSP was configured with GSI support in mind.)

---

## F15 — Nothing about this device is discoverable from marketing material

**Observation.** Retail listings and reviews disagree with the device about the battery
(advertised ~7000 mAh; `charge_full_design` reports 2,940,000 µAh) and give no useful
platform detail at all.

**Resolution.** Every specification in `docs/01-device-profile.md` and
`docs/02-firmware-forensics.md` that matters was read from `getprop`, the scatter file, or
parsed out of an image — not from a product page. Treat vendor marketing as unverified.

---

## F16 — The device is UFS, not eMMC (corrected mid-project)

**Symptom.** I documented "eMMC" because `MT6789_Android_scatter.txt` opens with
`storage_type: EMMC` and `ro.vendor.mtk_emmc_support=1` is set.

**Truth.** MTK scatter files contain **both** an EMMC and a UFS layout in one file, and the
flasher selects one at runtime; `mtk_emmc_support` is a BSP capability flag, not a statement
about this unit. The device is UFS 2.2:

- `ro.boot.boot_devices = bootdevice,soc/11270000.ufshci`
- `/sys/bus/platform/devices/11270000.ufshci/` exposing `device_descriptor`,
  `geometry_descriptor`, `health_descriptor`
- `sda`/`sdb`/`sdc` block naming, no `mmcblk0`
- UL PCMark: 896 MB/s sequential read

**Resolution.** Corrected in `02-firmware-forensics.md` §5.1/§9 and `appendix-a`.
**Lesson:** on MTK, the scatter file describes the *platform*, not the unit. Confirm the
storage bus from `ro.boot.boot_devices` before repeating what the scatter says.

---

## F17 — `vbmeta_system` and `vbmeta_vendor` cannot be flashed over fastboot on this device

**Symptom.** Every generic MTK GSI guide says to disable verification on three images:
`vbmeta`, `vbmeta_system`, `vbmeta_vendor`. Attempting that here fails, because the
partitions are not addressable:

```
$ fastboot getvar partition-size:boot_a           -> 4000000     (known)
$ fastboot getvar partition-size:vbmeta_a         -> 800000      (known)
$ fastboot getvar partition-size:dtbo_a           -> 800000      (known)
$ fastboot getvar partition-size:vbmeta_system_a  -> (empty)
$ fastboot getvar partition-size:vbmeta_vendor_a  -> (empty)
$ fastboot getvar partition-size:tee_a            -> (empty)
$ fastboot getvar partition-size:gz_a             -> (empty)
```

`vbmeta_system_a`, `vbmeta_vendor_a`, `tee_a`, `gz_a` all exist in the GPT but LK does not
publish them to fastboot, in either bootloader mode or `fastbootd`.

**Resolution / plan.** Use the two levers that *are* available:

1. the top-level `vbmeta_a` — the only vbmeta we can flash — with
   `HASHTREE_DISABLED|VERIFICATION_DISABLED` (flags=3), relying on AVB treating top-level
   flags as global across the chain;
2. `fastboot oem cdms`.

If verification still blocks boot, escalate to SP Flash Tool, which writes by scatter address
and does not care what fastboot publishes.

**Lesson.** "Not in `getvar all`" does not mean "not in the GPT", and vice versa. On MTK the
two views differ, and only the scatter/GPT is authoritative.

---

## F18 — `fastboot oem cdms` exists (MTK's dm-verity reset) — and the LK confirms it

**Finding.** `strings lk.img` contains a complete MTK managed-verity implementation:

```
clear_dm_verity_status
get_dm_verity_status
avb.managed_verity_mode
Error clearing avb.managed_verity_mode.
Error writing to avb.managed_verity_mode.
[FASTBOOT] Start reset dm-verity status.
external/lib/libavb_user/avb_user_verity.c
oem cdms
```

Combined with `ro.boot.veritymode.managed=yes`, this means MTK keeps its **own** dm-verity
state on top of AVB, stored via `avb.managed_verity_mode`. Clearing the AVB flags alone may
therefore be insufficient — `fastboot oem cdms` is the device-specific lever, and it is
present.

Other `oem` commands this LK exposes: `dump_pllk_log`, `get_key`, `get_socid`,
`off-mode-charge`, `p2u`, `printk-ratelimit`, `set_enckey`, `ultraflash`, `ultraflash_en`,
`usb2jtag`. Note there is **no** `oem unlock` / `oem device-info` — unlock is the standard
`fastboot flashing unlock`.

---

## F19 — `mtkclient` is not on PyPI, and MT6789 is not a BROM target

**Symptom 1.** `pip install mtkclient` → `ERROR: No matching distribution found for
mtkclient`. My first Dockerfile wrapped the install in a chain ending in `|| true`, so the
build "succeeded" with **no mtkclient present** — a silent failure that would have surfaced
only when someone tried to take a backup.

**Symptom 2.** Even with mtkclient installed, the documented "hold a volume key, get BROM
`0e8d:0003`" entry does not apply. mtkclient's README lists **MT6789** among the **V6** SoCs:

> *These chipsets use a new protocol called V6 and the bootrom is patched. You need to use the
> `--loader` option and a proper loader from the `Loaders/V6` directory. Bootrom won't work,
> you need to use preloader mode (no hw buttons pressed, just connect).*

**Resolution.** Install from source, and use preloader mode with the OEM's own DA:

```dockerfile
RUN python3 -m venv /opt/mtk && \
    /opt/mtk/bin/pip install --no-cache-dir --no-deps "git+https://github.com/bkerler/mtkclient" && \
    /opt/mtk/bin/pip install --no-cache-dir pyusb pycryptodome pycryptodomex colorama pyserial
```

(`--no-deps` drops the ~500 MB PySide6 GUI; the CLI is all we need.)

```bash
mtk --loader FW/…/images/download_agent/DA_BR.bin printgpt
```

`DA_BR.bin` is the OEM's signed Download Agent, shipped in the firmware package — which is
exactly what the maintainer recommends when the generic path fails on V6.

**Lesson.** Never let a dependency install sit behind `|| true` in a Dockerfile that documents
that dependency as available. Verify every tool the procedure relies on.

---

## F20 — Delegated research wrote outside the project tree

**Symptom.** Three research subagents completed but wrote their reports to `/opt/data/*.md`
(the agent home), not into the project.

**Resolution.** Moved to `research/sub-01-device-dossier.md`,
`research/sub-02-mtk-gsi-practice.md`, `research/sub-03-backup-and-drm.md`, and folded into
the numbered docs. Worth stating paths explicitly in any future delegation prompt.

---

## F21 — The OTA certificate is NOT the AOSP test key (a claim I got wrong, and fixed)

**What I claimed.** `otacerts.zip` contains a file called `testkey.x509.pem`, so I concluded
the device trusts the AOSP test key — and therefore that we could sign our own OTA/DSU
payloads.

**What is actually true.** The filename is a lie. The certificate is a **Techvision
self-signed cert**:

```
subject = C=zh, ST=Guangdong, L=Shenzhen, O=Huiweizhineng, OU=Ruanjian,
          CN=Bing, emailAddress=bing_wu@techvision.com.cn
validity = 2023-03-31 .. 2050-08-16
```

(`Huiweizhineng` = 慧为智能 = Techvision Intelligent.) Compared byte-for-byte against the real
AOSP `testkey.x509.pem` fetched from `platform/build`:

```
92543d0d...  testkey.x509.pem        1476 bytes   (device)
a4384ba8...  aosp-testkey.x509.pem   1675 bytes   (AOSP)
```

Different size, different hash, different subject. Not the same key.

**Consequences — this is the most consequential correction in the project:**

1. **We hold no private key that this device trusts** — not the AVB root, not the boot chain,
   not `vbmeta_system`/`vbmeta_vendor`, not the OTA cert. Everything must be done by
   *disabling* verification, never by signing something that verifies.
2. **DSU is probably blocked.** It verifies payloads against `otacerts.zip`; a Google-signed
   GSI won't match, and neither would anything we sign. The "sign our own GSI so DSU accepts
   it" idea is dead.
3. The lowest-risk test path shifts to **SP Flash Tool `Download Only`** of a rebuilt
   `super.img`, which bypasses signature checks entirely because it writes at the storage
   level — and needs no unlock.

**Lesson.** Verify key material by comparing bytes, not by trusting filenames. I would have
carried this error into the procedure and wasted a session chasing a DSU install that could
never have validated.

---

## F22 — My Phase 7 `lpmake` command was missing `--virtual-ab`

**Symptom.** The first draft of the `super.img` rebuild command did not pass `--virtual-ab`.

**Why that matters.** `lpdump` on the stock image reports `Header flags: virtual_ab_device`.
`lpmake` only writes that flag when told to:

```
$ lpmake 2>&1 | grep -A1 virtual
  --virtual-ab                  Add the VIRTUAL_AB_DEVICE flag to the metadata
```

A rebuild without it produces liblp metadata that does not declare Virtual A/B, which is not
the device the bootloader expects — a straightforward way to hand yourself a device that
refuses to boot and blames you.

**Related constraint it relaxes:** legacy A/B requires each group to be ≤ half of `super`
(≈4.5 GiB here). With `--virtual-ab` the full `9663676416` bytes are addressable, which is why
`main_a:9663676416` is legitimate in that command and would not be under legacy A/B.

**Resolution.** Added `--virtual-ab`, plus the three other values that must be copied from
`lpdump` rather than guessed (`--metadata-slots 3`, `--device super:9663676416`, group names
`main_a`/`main_b`), plus a `lpdump` verification step on the output.

---

## F23 — SP Flash Tool's three modes are not interchangeable, and I conflated two of them

**Symptom.** My appendix said a *Firmware Upgrade* flash "reformats the whole storage device"
and therefore wipes `persist`/`nvdata`/`seccfg`. Elsewhere I correctly said never to use
*Format All*. Those are two different modes and I had merged them.

**Truth:**

| Mode | Behaviour |
|---|---|
| **Download Only** | writes only the ticked partitions; touches nothing else |
| **Firmware Upgrade** | rewrites the partition table and downloads every image in the scatter; at minimum wipes `userdata`. This is the mode the vendor's own PDF recommends |
| **Format All + Download** | erases the whole flash including factory/calibration areas first — the documented Widevine-L1 killer |

`Firmware Upgrade` *may* rewrite partitions that carry no image in the package, which is why
dumps still matter — but calling it equivalent to `Format All` was wrong, and it is the
vendor's own recommended recovery mode.

**Resolution.** Appendix A now has the three-mode table with an explicit "use it?" column, and
Phase 7 specifies **Download Only** so the question never arises for the GSI path.

---

## F24 — `max-download-size` is the MTK fastbootd go/no-go, and ours is fine

**Finding.** A well-known MTK fastbootd failure is `getvar max-download-size` returning `no`,
after which fastboot dies on any multi-GB image with
`couldn't parse max-download-size 'no'` / `FAILED (remote: 'Invalid size')`.

**On this device it is a clean pass:**

```
$ fastboot getvar max-download-size
(bootloader) max-download-size: 0x4000000        # 64 MiB, so fastboot chunks correctly
```

**Resolution.** Added to Phase 4 as a documented pre-flight check, with the instruction to fall
back to Phase 7 if it ever returns `no`. This is cheap insurance: had it failed, the entire
fastbootd route would have been a dead end we'd have discovered mid-flash.

---

## F25 — `adb reboot edl` reaches the preloader, but mtkclient cannot handshake there

**Question this answers:** "can't you just reboot it via adb instead of making me power-cycle?"

**Yes, partly.** `adb reboot edl` genuinely works on this device. Measured with `lsusb`:

```
t+0s    0e8d:201c   Techvision T3_US           (Android)
t+4s    0e8d:2000   MediaTek MT65xx Preloader  <- preloader mode
t+8s    (no device)                            <- window closed
t+24s   0e8d:201c   Techvision T3_US           (booted back to Android by itself)
```

So the mode is reachable hands-free, and the tablet recovers on its own every time — no
button, no intervention, no brick. LK has no `edl` reboot target (only `reboot-fastboot` /
`reboot-recovery`), so the handoff is kernel → preloader, not LK → fastboot.

**But mtkclient cannot complete a session in that mode.** With it already scanning, it finds
the device and then fails:

```
..........Preloader
Preloader - [LIB]: Status: Handshake failed, retrying...
```

Repeated twice, at debug log level, with **no** USB/permission error and no traceback — the
port opens fine, the preloader simply doesn't answer mtkclient's handshake. The likely reason:
`reboot edl` enters MTK's **emergency download mode** (the preloader literally contains
`"%s emergency download mode(timeout: %ds)."`), which is SP Flash Tool's protocol, not the
preloader download protocol mtkclient speaks. The window is also only a few seconds.

**Conclusion.** `adb reboot edl` is useful for *proving the mode exists*, and would be the
right entry point for SP Flash Tool. For mtkclient the supported path remains a **cold**
preloader start: power off, then connect USB with no buttons. That is a physical action and
cannot be scripted from here.

---

## F26 — mtkclient 2.1.4's `--vid`/`--pid` flags are broken (list vs dict)

**Symptom.** Passing `--vid 0x0e8d --pid 0x2000` made things strictly worse — the device was
never even considered.

**Cause.** Two different `portconfig` shapes in the same code path:

- `Library/mtk_class.py:159` — when you pass `--vid`/`--pid`, it builds
  `portconfig = [[vid, pid, interface]]`, a **list of lists**.
- `Library/Connection/usblib.py:339` — the matcher does
  `if dev.idVendor in self.portconfig and dev.idProduct in self.portconfig[dev.idVendor]`,
  which assumes a **dict**.

So `0xE8D in [[0xE8D, 0x2000, 10]]` is `False`, always. Confirmed directly:

```
>>> u = UsbClass(portconfig=[[0xE8D, 0x2000, 10]])
>>> type(u.portconfig), 0xE8D in u.portconfig
(<class 'list'>, False)
```

The **default** path is fine, because `config/usb_ids.py:default_ids` *is* a dict — and it
already contains the preloader PID:

```
0xe8d: 0x2000, 0x2001, 0x201d, 0x20ff, 0x3, 0x3000, 0x6000
```

**Resolution.** Do **not** pass `--vid`/`--pid`. The default dict already covers `0x2000`
(preloader) and `0x0003` (BROM). Passing the flags silently disables all port matching.

**Lesson.** A CLI flag that *narrows* the search can narrow it to nothing. When a tool says
"can't find device" and you added a filter, remove the filter before believing the hardware.

---

## F27 — mtkclient cannot handshake this preloader at all; SP Flash Tool Readback is the path

**Result after five attempts across every entry mode.** mtkclient reliably *binds* the
preloader and then fails the handshake:

```
..........Preloader
Preloader - [LIB]: Status: Handshake failed, retrying...
```

Attempts and outcomes:

| # | Entry | Result |
|---|---|---|
| 1 | `mtk printgpt`, `adb reboot edl` | caught `0e8d:2000`, handshake failed |
| 2 | `--vid 0x0e8d --pid 0x2000` | never matched — the flag path is broken (F26) |
| 3 | `--loglevel debug`, `adb reboot edl` | handshake failed, no USB/permission error, no traceback |
| 4 | cold power-on, no key | preloader seen on the bus, mtk never bound (window closed first) |
| 5 | cold power-on, volume key held | bound, then **3** handshake failures |
| 6 | cold power-on, **Volume Up held** (instrumented) | **5** handshake failures; Vol+ opens LK's boot menu, not download mode |

**Diagnosis.** It is not timing and not the host: the port opens, the device is identified as
`Preloader`, and the exchange is refused. This unit is MT6789 with `seccfg` locked, `secure: yes`
and the vendor shipping `SLA_Challenge.dll`, i.e. Download Agent authentication is in play — the
initial `0xA0` handshake is not accepted in the way mtkclient 2.1.4 expects for this generation.

**Correction to an earlier inference in this log.** I briefly concluded that holding a volume key
keeps the preloader in download mode, because attempt 5 bound where attempt 4 had not. That was
wrong, and attempt 6 disproved it: **Volume Up at power-on opens LK's boot menu** ("normal boot /
fast boot / recovery boot"), which is a UI that runs *after* the preloader has already exited.
So no key holds this preloader open — the window is simply short (a few seconds), and the binding
in attempt 5 was luck within it, not a consequence of the key.

**Conclusion.** mtkclient is out for the backup on this device. The supported tools are the
vendor's: **SP Flash Tool → Readback**, with `DA_BR.bin` and `SLA_Challenge.dll` from
`Tool/SP_Flash_Tool_V6/`. That is Windows-only — a VM with USB passthrough is enough.

**Consequence that changes the plan.** The per-unit dump was framed as a hard gate because
unlocking risks the TEE. But the recommended route is SP Flash Tool **`Download Only`** of a
rebuilt `super.img`, which writes *only* `super` and never touches `persist`, `nvdata`,
`nvram`, `proinfo` or `seccfg`. So the dump is **insurance against a botched recovery**, not a
precondition for the flash. It is entirely reasonable to proceed without it and take the dumps
later from a Windows session.

**Lesson.** When a tool's own README hint and the hardware disagree, the hardware wins — and
"it bound but the handshake failed" is a protocol verdict, not a timing problem. Say so and
change tools rather than retrying the same path.

---

## F28 — adb trust is per key, so a new container starts `unauthorized`

**Symptom.** `adb devices` inside the tools container showed `SERIAL-DAILY unauthorized`,
while the same tablet showed `device` inside the REA container.

**Cause.** Android's adb authorisation is a trust relationship with a specific **RSA key**
(stored on the device in `/data/misc/adb/adb_keys`), not with the host or the container. Each
container's adb generates and uses its own `~/.android/adbkey`, so a fresh one is a stranger —
hence the `Allow USB debugging?` prompt, which a headless container can never answer.

**Resolution.** Reuse the key the tablet already trusts instead of trying to authorise a new one:

```bash
docker cp rea-agent-ghidra:/home/rea/.android/adbkey     /opt/data/.android/adbkey
docker cp rea-agent-ghidra:/home/rea/.android/adbkey.pub /opt/data/.android/adbkey.pub
chmod 600 /opt/data/.android/adbkey
```

then mount `/flashcache/hermes/.android` at `/root/.android` in the tools container. Result:
`device`, and `adb shell` works.

Two constraints worth recording:

- **The key is private.** It lives at `/opt/data/.android`, *outside* the project tree, so it
  cannot end up in the publishable documentation. Never copy it into the repo.
- **Only one adb server may hold the USB interface.** With both containers' adb daemons alive
  they fight over the device; `adb kill-server` in the REA container first. This is also why a
  persistent `android-tools` container (kept up with `sleep infinity`, driven via
  `work/at.sh`) is better than `docker run --rm` per command — one long-lived server, no churn.

**Lesson.** `unauthorized` is not a permissions bug on the host; it is a missing key pair on the
device. Copying an already-trusted key is faster and more reproducible than prompting a human.

---

## F29 — This LK has an on-screen boot menu (normal / fastboot / recovery)

**Finding.** Holding **Volume Up** while powering on does **not** enter download mode. It brings
up LK's boot menu offering:

```
normal boot     fast boot     recovery boot
```

That is a UI stage that runs *after* the preloader has handed over, so it is useless for
preloader/Download-Agent work — but it is genuinely valuable as a **manual recovery entry
point**: if `adb` is dead and `adb reboot bootloader` is unavailable, this menu reaches fastboot
and recovery with hardware keys alone.

Worth recording because it is the only hardware-only path into fastboot on this device, and
because it disproves the natural assumption that the volume-key hold gets you into MTK download
mode. The preloader is **headless** — it has no screen; on the host it is nothing but
`0e8d:2000 MediaTek MT65xx Preloader` appearing for a couple of seconds.

---

## F30 — The preloader enumerates as CDC ACM, and the host kernel claims it (probable root cause)

**Finding.** Captured the preloader's actual USB descriptors for the first time:

```
iConfiguration  "USB CDC ACM for preloader"
bDeviceClass    2   (Communications)
bNumInterfaces  2
  Interface 0: class 2 / subclass 2  (CDC ACM control)  + interrupt EP 0x83
  Interface 1: class 10              (CDC Data)         + bulk EP 0x01 OUT / 0x81 IN, 512B
```

It is a **CDC ACM serial device**, not a vendor-specific bulk device. And the host kernel
binds it automatically:

```
cdc_acm 3-1:1.0: ttyACM0: USB ACM device
cdc_acm 3-1:1.1: probe with driver cdc_acm failed with error -22
```

**Why this explains everything we saw.** Once `cdc_acm` owns those interfaces, a userspace
libusb client can enumerate and open the device and read its descriptors — so mtkclient prints
`Preloader` and looks like it is talking — but it cannot claim the CDC interfaces, so the
handshake exchange gets no response and times out as `Handshake failed, retrying...`. No USB
or permission error is reported, which is exactly what we observed across nine attempts.

It also explains `DeviceClass - [LIB]: Couldn't get device configuration` on `0e8d:20ff` (the
LK boot menu's port) — same class of contention.

**The fix to test.** Stop `cdc_acm` from binding before the attempt:

```bash
modprobe -r cdc_acm          # on the HOST; reversible with: modprobe cdc_acm
```

Then power-cycle into preloader mode and rerun `mtk printgpt`. Unbinding live is impractical
because the window is only 2–4 s, so removing the module for the duration of the attempt is the
right shape. This is a **host kernel** change (narrow: only CDC ACM devices, and reversible),
so it needs explicit approval before being run.

**Note for the Windows/VM route.** The same ownership matters for USB passthrough: QEMU can
detach host drivers, but the critical detail is that this device **re-enumerates between PIDs**
during download — we observed `0e8d:20ff` (boot-menu port) → `0e8d:2000` (preloader) →
`0e8d:0003` (BROM) → `0e8d:200e` (factory/META) → `0e8d:201c` (Android) within a few minutes.
So passthrough must be by **vendor id (`0x0e8d`) with hotplug**, not a fixed `vendor:product`,
or the VM will lose the device mid-flash.

**Timeline capture** (`backup/usb-watch2.txt`) also shows the preloader appears for **2–4
seconds** on every boot, and `0e8d:0003` (BROM) for ~5 s — so BROM is briefly reachable, but it
is patched on V6 and mtkclient's BROM path does not apply.

---

## F31 — Pinning the preloader interface to 1 was necessary but not sufficient

**What was wrong.** `config/usb_ids.py` ships `0x2000: -1` for the MTK preloader. With `-1`,
mtkclient's interface selection falls back to **interface 0** — which on this device is the
CDC *control* interface with only an interrupt endpoint. The bulk endpoints it needs
(`0x01`/`0x81`, 512 B) live on **interface 1** (CDC Data). So the handshake was being aimed at
an interface with no bulk endpoint at all.

**Patched:** `0x2000: -1` → `0x2000: 1` in the container image (`lincplus-android-tools:5`).

**Result:** the code path changed as predicted — the `No interface matched devclass, using
interface 0` message disappeared — but the handshake still fails, **11 times across four
preloader windows** (~2.75 attempts per window). That rate matters: it means mtkclient is
reaching the handshake and being *refused*, not running out of time. The window is 2–4 s, which
is ample for the ~200 ms an attempt takes.

**Conclusion.** Two independent defects, in sequence:

1. the wrong interface (fixed — and worth fixing; it was a genuine bug), and
2. a preloader that will not complete the `0xA0` exchange with this client, consistent with
   Download Agent authentication on a locked unit.

There is no third lever available from Linux userspace. The vendor's own stack
(`DA_BR.bin` + `SLA_Challenge.dll`) is designed for exactly this and is the correct tool.

**Also learned:** `modprobe -r cdc_acm` does **not** keep the driver away — udev re-`modprobe`s
it within ~2 s of the device appearing, so that experiment was invalidated rather than
negative. Preventing the bind would need a `modprobe.d` blacklist plus a udev rule, which is a
host-wide change disproportionate to the payoff once F31 was found.

**Lesson.** Fix the concrete bug you can prove (wrong interface number) even when it doesn't
resolve the whole failure — it converts a vague "handshake failed" into a specific "refused",
which is what finally justified changing tools instead of retrying.

---

## Open questions carried into the flashing phase

| # | Question | How to settle it cheaply |
|---|---|---|
| Q1 | Does `fastboot flash system` work despite the missing `IFastboot` HAL (F12)? | attempt the flash with the stock firmware ready; `max-download-size` and `is-logical` both report correctly, so this is likely fine |
| Q2 | Does a **cold** preloader entry let mtkclient read this unit? (adb `reboot edl` reaches the mode but the handshake fails — F25) | `mtk --loader DA_BR.bin printgpt` with the tablet fully powered off, no `--vid`/`--pid`. **If this fails there is no backup, and the unlock becomes a one-way bet on Widevine L1.** |
| Q3 | Does DSU work at all here, given only a Techvision cert is trusted? | one attempt; expect rejection. If rejected, go to Phase 7 (SP Flash Tool `Download Only`) rather than unlocking |
| Q4 | Does Widevine stay L1 after a system-only swap + unlock on *this* TEE? | `dumpsys media.mediadrm` before and after; no way to know in advance |
| Q5 | Does top-level `vbmeta` flags=3 suffice, or does MTK managed verity need more? | boot attempt; if refused, `oem cdms`, then SP Flash Tool for `vbmeta_system` |
| Q6 | Is the Primebook's `tb8781p1_64_wifi` board string real? | if yes, an Android 15 vendor BSP exists for this board |

---

## F32 — Containerised QEMU cannot open this device on re-enumeration

**Context.** With mtkclient refused (F27) and the preloader unable to complete its handshake
(F31), the vendor's own stack became the intended path: SP Flash Tool v6 in a Windows VM, which
ships the authenticated `DA_BR.bin` and `SLA_Challenge.dll`. The VM was built and works. The USB
passthrough does not.

**What was fixed along the way (both real bugs).**

1. **`/dev/bus/usb` must be a bind mount, never a `devices:` entry.** A directory passed under
   `devices:` is *snapshotted at container creation*. usbfs nodes are
   `/dev/bus/usb/<bus>/<devnum>`, and `devnum` increments on every re-enumeration, so after the
   first boot cycle the container held node `076` while the tablet was on `086`. QEMU had no node
   to open and silently substituted a `USB Host Device` placeholder at 1.5 Mb/s. Converting to
   `- /dev/bus/usb:/dev/bus/usb` made the current node appear immediately.

2. **`cdc_acm` owns the preloader interfaces and must be stripped per-window.** Measured:
   udev binds `cdc_acm` to `3-1:1.0` and `3-1:1.1` at **+100–150 ms** after the preloader
   enumerates, and holds them. Unbinding *before* udev binds is a silent no-op (the interfaces do
   not exist yet). Unbinding *after* it binds works and **sticks** — verified by sampling the
   interface→driver map every 50 ms for 3 s, with both interfaces staying `none` throughout.
   The write must come from a container with host `/sys` writable; the Hermes container mounts it
   read-only, but the privileged Windows container has it rw.

**What could not be fixed.** Even with the preloader caught at 20 ms resolution, `cdc_acm`
stripped 143 ms in, and both remaining free — QEMU still did not open the device:

| Attempt | Result |
|---|---|
| Boot-time `-device usb-host,vendorid=0x0e8d` | ✅ opens — `info usb` shows `Product T3_US` |
| QMP `device_add` by `vendorid` (+ productid) | ❌ `USB Host Device` placeholder, always |
| QMP `device_add` by `hostbus=3,hostport=1` | ❌ placeholder (note: `hostport` must be a **string**) |
| Fresh filter, no stale handle, then real hotplug of `0e8d:2000` | ❌ placeholder |
| Device present and stable with **no** driver bound, then add | ❌ placeholder |

So QEMU opens this device only at VM start. On re-enumeration it leaves a dead slot —
consistent with the `libusb_release_interface: -4 [NO_DEVICE]` it logs — and Windows therefore
never sees `PID_2000`, never gets an MTK VCOM COM port, and SP Flash Tool has nothing to connect
to. `C:\MTK\backup` stays empty.

**Conclusion.** Containerised QEMU is the wrong layer for this device. The preloader lives
~2.7 s and re-enumerates with a new `devnum` every boot; that is exactly the case a hypervisor
USB filter handles worst.

**Recommendation.** Do the readback on physical Windows hardware — it is a five-minute job there.
The partitions are insurance, not a precondition: the no-unlock `Download Only` route in
`docs/07-procedure.md` (Phase 7) never writes `persist`/`nvdata`/`nvram`/`proinfo`/`seccfg`, so
work can continue without them. Only an unlock-first plan (fastboot route) makes the absence of
a backup a one-way bet, and that route is already the less preferred one for Widevine L1.

**Two incidental traps, recorded because both cost time.** Windows OpenSSH **kills a session's
descendant processes when the connection closes** — a `Start-Process`'d child survives only for
the duration of the call; launch long jobs through `Invoke-CimMethod Win32_Process Create`
(parented to `WmiPrvSE`) instead. And PowerShell 5.1 reads a **no-BOM UTF-8** `.ps1` as ANSI, so
an em dash in a comment or string decodes to a `"` byte and breaks string termination with a
bewildering "missing terminator" error — keep helper scripts pure ASCII.

---

## F33 — Console mode cannot read; the GUI Readback tab can (backup obtained)

**Outcome: the per-unit backup is complete and verified.** 58 partitions (~10.2 GB) read from the
unit with SP Flash Tool v6.2208.00 GUI → Readback → **Auto**, and the eleven irreplaceable ones
(`persist`, `nvram`, `nvdata`, `proinfo`, `seccfg`, `protect1/2`, `nvcfg`, `otp`, `metadata`,
`frp`) copied off, SHA256-verified, and stored at `backup/readback/` with a manifest.

**The working procedure** (now the primary one in `physical-readback/README.md`):

1. GUI → **Download** tab → *Download-XML* → `images/download_agent/flash.xml` (vendor's own).
2. **Readback** tab → radio button **Auto** (not Manual) → rows populate from the XML.
3. Untick `userdata`, press **Readback** → tablet powered off, plugged in.
4. Files land in `tool/SP_Flash_Tool_V6/Readback/` as bare partition names, no extension.

**Why console mode was abandoned.** `SPFlashToolV6.exe -i config.xml` validates the schema and
connects — `connect brom successed.` — but every read command then fails:

```
CMD:READ-PARTITION command execute failed, error code: -1, msg: No such node (brom.version)
```

`READ-FLASH` fails identically. That is an internal config-tree lookup: console mode never
populates the DA context the read commands run against. Each `conn_stage` value was tested —
`brom` connects then fails on the command; `1st DA` and `2nd DA` fail *during* connect (a 1–16 s
stall, empty error message), because they expect a device already at that stage. MediaTek's own
shipped examples (`read_efuse.xml`, `write_efuse.xml` in the `SP_Flash_Tool_Linux` GitHub repo)
use `conn_stage="2nd DA"`, which is what pointed at the stage theory in the first place; it is
simply not applicable to a fresh preloader. **Conclusion: console-mode read is not functional on
this build. Use the GUI.**

**Device-state findings, each of which invalidated a whole test round:**

- **Plugging in a powered-off unit raises the preloader by itself** — no power button needed.
  Pressing power afterwards is not just unnecessary, it can move the device on to Android.
- **The preloader goes stale within seconds** and then answers the handshake with `ACK 0x5F`
  instead of `0xA0` (`BROM protocol error`). A stale one stays enumerated indefinitely, so
  "device present" says nothing about whether it will answer.
- **Unplugging USB does not kill it** — the tablet has a battery and the charge LED stays lit.
  Only a real shutdown plus a fresh power-on yields a responsive preloader.
- **A Windows PnP device reset does not revive it** (Disable/Enable left it answering `0x5F`).
- A helper that decides "is the device there?" **must** use `Get-PnpDevice -PresentOnly`;
  without it, the stale `Status Unknown` node makes the check permanently true.

**The `C:\Users\Mei\Desktop\...flash.xml is not exist` startup error** is a stale MRU entry in
`tool/SP_Flash_Tool_V6/history.ini`, inherited from the vendor's build machine — the tool ships
inside the OEM firmware package, so its history lists Techvision's own `TVE1070M`/`TVE1079M`
firmware builds. It is not a missing file; rename `history.ini` to `history.ini.bak`.

**Also confirmed:** `TVE1070M` (Techvision OEM model) and `T3_US`/Lincplus T3 are the same
hardware — same `tb8781p1_64_wifi` board, which is why the vendor `flash.xml` matches the device.

**Integrity cross-check, physical partitions vs OEM package.** Comparing partitions that exist
both as physical partitions (readable by Readback) and as shipped `.img` files proves the OEM
package matches the unit and the dump is genuine:

| Partition | OEM `.img` | Readback | |
|---|---|---|---|
| `boot` | `7eb7086e…abd3` | `7eb7086e…abd3` | identical |
| `dtbo` | `cd78fdf8…e5b` | `cd78fdf8…e5b` | identical |

`tee` and `lk` can't be hashed this way — the shipped `.img` is the image while the partition is
padded to its full size (`tee`: 2,789,536 vs 5,242,880; `lk`: 2,184,048 vs 4,194,304) — compare
the first *image-size* bytes instead if needed.

**Note for anyone repeating this:** logical partitions inside `super` (`system`, `vendor`,
`vendor_dlkm`, `odm_dlkm`, `product`, `odm`) do **not** appear individually in a Readback dump,
because Readback reads physical partitions. `super` itself does. To inspect a logical partition,
unpack `super` with `lpunpack -p <name>`.

## F34 — The OEM package's `boot-debug.img` gives root on stock Android (no Magisk)  {#f34}

**Outcome: root on a fully stock `user` build, using nothing but a file the vendor ships.**

Flashing `images/boot-debug.img` from the firmware package to `boot` makes `adb root` succeed and
`adb shell id` report `uid=0(root)` with context `u:r:su:s0`, on a system that still reports
`Lincplus/T3_US/T3_US:13/TP1A.220624.014/20241016:user/release-keys`. `ro.debuggable` becomes `1`.

The mechanism is inside the image's ramdisk — two entries beside the usual ones:

| Entry | Purpose |
|---|---|
| `force_debuggable` | tells init a debug property file is present |
| `adb_debug.prop` | `ro.adb.secure=0`, `ro.debuggable=1`, `ro.force.debuggable=1` |

`adb_debug.prop`'s own header states it is honoured only when a `/force_debuggable` ramdisk is used
**and the device is unlocked** — which is exactly the precondition we create by unlocking.

Two prerequisites that are easy to miss:

- The **bootloader must be unlocked**, or the property override is ignored.
- **`vbmeta` must allow the modification.** With the stock `vbmeta` (hash descriptors present) the
  debug boot is discarded; flashing `vbmeta` with `Flags: 3` (verity + verification disabled) makes
  it take effect. This is also why a Magisk-patched `boot` silently did nothing before that change.

**Don't bother with the Magisk route on this device.** A host-patched `boot` (Magisk 27.0,
`magiskboot` x86_64, `boot_patch.sh`) produced a structurally correct image — `init` replaced by
`magiskinit`, `overlay.d/sbin/magisk64.xz` present — and Magisk's own app still reported
`Installed: N/A, Ramdisk: Yes` afterwards. `boot-debug.img` gets root in one flash with no patching.

## F35 — Unlocking does **not** cost Widevine L1. The GSI does.  {#f35}

**Outcome: measured, not inferred — and it contradicts the usual assumption.**

Three states measured on the same unit with the same app:

| Field | stock, **locked** | stock, **unlocked** | **GSI** (LineageOS 21) |
|---|---|---|---|
| Security level | **L1** | **L1** | **L3** |
| System ID | `29739` | `29739` | `28917` |
| Max HDCP | HDCP 2.3 | HDCP 2.3 | None |
| Max sessions | 50 | 50 | 16 |
| CDM version | `16.1.1@006` | `16.1.1@006` | `16.1.1@006` |

Phase B is identical to Phase A on every DRM field with `verifiedbootstate` already `orange`, so
the unlock costs nothing. Phase C moves four values at once while the CDM version is unchanged —
the signature of a *different CDM instance*, not a degraded one: the GSI bundles its own software
Widevine and it shadows the vendor's hardware-backed L1 CDM. The vendor HAL stays up throughout
(`android.hardware.drm@1.1::IDrmFactory/widevine`).

So the popular advice "unlocking kills Widevine" is wrong for this device, and the real trade-off
of a GSI is stated plainly: Android 14, but HD playback capped at L3.

## F36 — PairIP survives a sideload and hides behind the Application class  {#f36}

**Outcome: the licence check runs from `com.pairip.application.Application`, not from
`LicenseActivity` alone.**

Sideloading `com.androidfung.drminfo` 1.2.2 shows the UI for a moment, then Play Store opens.
Logcat names the culprit: `com.pairip.licensecheck.LicenseActivity`, then
`Activity top resumed state loss timeout`. With root, disabling just that activity is enough and the
app then runs normally:

```bash
adb shell pm disable com.androidfung.drminfo/com.pairip.licensecheck.LicenseActivity
adb shell am start -n com.androidfung.drminfo/.MobileActivity
```

Details worth knowing:

- On a `user` build this **requires root** — the shell user gets
  `SecurityException: Shell cannot change component state ... to 2`.
- `MobileActivity` already holds the `LAUNCHER` category; nothing needs repointing.
- Repackaging the APK is not a workaround here: `apktool` cannot rebuild it (unresolved Material3
  attrs such as `state_dragged`), so the manifest edit route is closed.
- The APK is signed by cert SHA1 `4a2395a2ae05637a90c58876322818448c586d31` and carries a Play
  SourceStamp — verify that before installing anything from a mirror.
- Mirrors block scripted downloads (APKPure/APKFab 403). A real browser fetched
  `d.apkpure.com` fine; the MCP's own downloader does not, because it has no session cookies.

## F37 — A GSI loses Widevine L1 to *provisioning refusal*, and stock identity restores it  {#f37}

**Outcome: Android 14 GSI running with Widevine L1, HDCP 2.3, 50 sessions, System ID 29739 —
identical to stock.** Full recipe: `10-widevine-l1-on-gsi.md`.

The CDM is **not** in the GSI. Byte scans for `libwvhidl` / `libwvdrmengine` / `liboemcrypto`
return 5 / 63 / 12 in the OEM `vendor` partition and **0 / 0 / 0** in both the LineageOS 21 and
Google AOSP 14 system images. The same vendor CDM runs either way; what changes is whether it is
*provisioned*. Unprovisioned, it self-degrades to a provisional identity — which is why L3 shows a
different System ID (`28917`), 16 sessions instead of 50, and no HDCP, while the CDM version stays
`16.1.1@006`.

Provisioning is gated on the build identity. Patching the GSI's props so the composed fingerprint
reads `Lincplus/T3_US/T3_US:14/TP1A.220624.014/20241016:userdebug/release-keys` was enough to get
L1 back.

Two details that cost time and are worth knowing:

- **Patching `ro.product.system.*` alone does nothing.** init resolves `ro.product.*` from the
  first source in `ro.product.property_source_order` that defines it, and on a GSI that is the
  **product overlay inside `system.img`** (`/system/product/etc/build.prop`). A partial patch left
  `ro.product.brand=google` and the fingerprint still reading `google/lineage_arm64_bgN/...`, and
  Widevine stayed L3. Three files must be patched: `/system/build.prop`,
  `/system/product/etc/build.prop`, `/system/system_ext/etc/build.prop`.
- **Release and build type need not match stock.** `:14` and `userdebug` still provisioned L1.
  Keeping `userdebug` is what keeps `adb root` alive, which is what lets the PairIP-wrapped DRM app
  run at all (F36). Do not "fix" the fingerprint to `:13/user` or you lose the measurement tool.

Method note: Android system images are ext4 with `shared_blocks` and are typically 100% full, so
`mount -o rw` fails and `e2fsck -E unshare_blocks` cannot duplicate extents with no free space.
`debugfs` replaces the prop file in place, which is sufficient:
`debugfs -R "dump <path> /tmp/p"` → edit → `debugfs -w -R "rm <path>"` → `debugfs -w -R "write /tmp/p.new <path>"`.

Scripted as `build/patch-gsi-identity.sh`.

Caveat: this restores Widevine L1, not Play certification. SafetyNet/Play Protect still see a GSI
build, so banking and "device is certified" checks may still fail; HD playback works.
