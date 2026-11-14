# Brief — Windows in QEMU-in-Docker, for SP Flash Tool Readback

**Audience:** whoever builds the Windows-in-Docker image.
**Written by:** the GSI project (see `README.md`).
**Status:** the Linux-side attempt is exhausted; this is the next step, and this document
explains what it is for so the build is aimed at the real requirement.

---

## 1. Mission, in one paragraph

Build a Docker-run Windows VM on this Linux host, with the MediaTek tablet passed through over
USB, so that **SP Flash Tool v6 (a Windows-only Qt binary)** can perform a **`Readback`** of a
handful of per-unit partitions from the tablet. Nothing is flashed. The output is a set of
`.bin` files that exist nowhere else on earth and cannot be regenerated.

That is the whole purpose. It is not a general Windows VM, not a gaming/desktop setup, and not a
platform for flashing. It exists to run one 20 MB.exe against one USB device.

---

## 2. Why Windows, and why a VM

The tablet is a **Lincplus T3**, MediaTek **MT6789 / MT8781 (Helio G99)**, Android 13 on an
Android 12 vendor, bootloader **locked**, `secure: yes`.

We need to back up `persist`, `nvdata`, `nvram`, `proinfo`, `protect1/2`, `seccfg` before any
unlock, because a bootloader unlock can permanently destroy hardware DRM provisioning and
because the OEM firmware package ships these **blanked**. Root is unavailable (`user` build),
so the read must happen at the **preloader / download** level.

The open-source tool for that is **mtkclient**, and it does not work on this unit. Evidence, in
order of discovery:

| # | Finding |
|---|---|
| 1 | `mtk` binds the preloader (`Preloader` printed) then fails `Status: Handshake failed, retrying...` — no USB or permission error, no traceback |
| 2 | The preloader enumerates as **CDC ACM** (`"USB CDC ACM for preloader"`), so Linux auto-binds `cdc_acm` and creates `ttyACM0` |
| 3 | `modprobe -r cdc_acm` is **undone by udev within ~2 s** — that test is invalid, not negative |
| 4 | mtkclient ships `0x2000: -1` in `config/usb_ids.py`, which makes it claim **interface 0** (CDC control, interrupt endpoint only) instead of **interface 1** (CDC Data, bulk `0x01`/`0x81`). We patched it to `1` — a real bug, and it did not fix the failure |
| 5 | After the patch: **11 handshake attempts across 4 preloader windows**. Several attempts *inside* one 2–4 s window means the client is being **refused**, not timing out |

Conclusion: the preloader will not complete mtkclient's `0xA0` exchange with this unit. That is
consistent with **Download Agent authentication** — and the vendor's own tooling is built for
exactly that: the firmware package ships `images/download_agent/DA_BR.bin`, and
`Tool/SP_Flash_Tool_V6/` ships **`SLA_Challenge.dll`**. SP Flash Tool speaks that authenticated
protocol; nothing in Linux userspace does.

Hence: Windows, in a VM, in Docker, on the same host that already has USB access to the device.

**If the builder finds a way to make this work without Windows (e.g. a maintained
`spflashtool` Linux port or a current mtkclient branch that handles DAA), take it** — the
Windows VM is a means, not the goal. Section 3 is the real acceptance criteria.

---

## 3. What "done" looks like

A container that, on `docker compose up`, gives a Windows desktop reachable from this headless
host (VNC/noVNC in a browser is ideal — there is no display), in which:

1. **SP Flash Tool v6 launches** (`SPFlashToolV6.exe`; needs the VC++ redistributable).
2. **The MTK USB VCOM driver is installed**, from `Tool/MTK-Driver-v5.2307`.
3. **The tablet appears, survives re-enumeration, and can be read back.** Concretely, when the
   tablet is power-cycled, Windows' Device Manager shows the preloader/VCOM device appear, SP
   Flash Tool's **Readback** tab can attach, and it produces the partition files in §7.

Acceptance test: read back **`persist`** (a 55,264 KiB partition at `0x13208000`) and get a file
that is not all-zero and contains `53 EF` at offset `0x438` (ext4 superblock magic). That single
artefact proves the whole chain end to end.

---

## 4. Non-goals

- **Do not flash, format, or "Download Only" anything.** Readback is read-only. `Format All`
  on this device is a documented Widevine-L1 killer.
- Do not unlock the bootloader.
- Do not attempt to install Android tools, GSI images, or drivers other than the MTK VCOM one.
- Do not "fix" the tablet if it lands in a factory-test or boot-menu mode; a power cycle clears it.

---

## 5. The hard part: USB passthrough with re-enumeration

This is where the build will succeed or fail, so it is worth being precise.

**The device changes identity repeatedly.** Measured on the host over one session:

| PID | Meaning | Typical lifetime |
|---|---|---|
| `0e8d:201c` | Android (MTP/ADB composite) | steady while booted |
| `0e8d:20ff` | LK boot-menu USB port | until a boot option is chosen |
| `0e8d:2000` | **Preloader** — the one we need | **2–4 seconds** |
| `0e8d:0003` | BROM | ~5 seconds |
| `0e8d:200e` | factory/META test mode | until power-cycled |

Consequences for the VM:

- **Pass through by vendor ID only** (`0x0e8d`), never a pinned `vendor:product`. QEMU's
  `usb-host` supports `vendorid=` filtering and will re-attach as the PID changes; a pinned
  match silently drops the device mid-sequence and SP Flash Tool reports a disconnect.
- **The device must be attached before the tablet is powered on.** The preloader window is 2–4
  seconds; hot-plugging after the fact always misses it.
- Expect **Windows to see a disconnect/reconnect cycle** on each transition. That is normal and
  SP Flash Tool is designed for it. The MTK VCOM driver must be allowed to re-bind without
  prompting (`--privileged` containers give QEMU what it needs).
- The host kernel binds `cdc_acm` to the preloader. QEMU's `usb-host` detaches host drivers
  itself, so this should be a non-issue *inside* the VM — but if the guest never sees the
  device, check `dmesg` on the host for `cdc_acm ... ttyACM0` and note that a durable block
  would need a `modprobe.d` blacklist **plus** a udev rule (not just `modprobe -r`).

---

## 6. Host facts to build against

| | |
|---|---|
| Host | Debian, kernel `6.14.11-9-bpo12-pve` (Proxmox node) |
| Docker | available; the agent has access to the host Docker socket |
| Hardware accel | `/dev/kvm` exists — pass it through (`--device /dev/kvm`); software emulation will be unusably slow for a Windows install |
| USB access | device is on host bus 3 (`Bus 003 ... 0e8d:XXXX`); needs `--privileged` plus `-v /dev/bus/usb:/dev/bus/usb`, or explicit `usbfs` cgroup rules |
| Display | none. Use VNC + noVNC/web or a websocket VNC client |
| Windows media | **the user must supply a Windows ISO.** Do not assume a licence; do not download Windows from unofficial mirrors. A ~20 GB virtual disk is plenty |
| Persistence | put the VM disk on a mounted volume so a container rebuild does not lose the installed guest — see `/opt/data` ↔ `/flashcache/hermes` (same directory, two paths) |

**adb access from a container.** adb authorisation is per **key**, not per host: a fresh
container generates its own key and the tablet reports `unauthorized`. A key the tablet already
trusts exists on this host at `/opt/data/.android/adbkey` (copied from the REA container, which
the tablet was originally paired with), and is mounted into the tools container as
`/root/.android`. To reproduce it elsewhere:

```bash
docker cp rea-agent-ghidra:/home/rea/.android/adbkey     /opt/data/.android/adbkey
docker cp rea-agent-ghidra:/home/rea/.android/adbkey.pub /opt/data/.android/adbkey.pub
chmod 600 /opt/data/.android/adbkey
```

Note: that key is **deliberately kept outside this repository and is not reproduced in this
document**. These docs are written to be published, and a private key pasted into a public repo
hands anyone adb access to the owner's tablet. The path plus the commands above are the quick
reference; the key material itself stays in `/opt/data/.android` with mode 0600. Also, only one
adb server may hold the USB interface at a time — run `adb kill-server` in the REA container
before using the tools container.

**Recommended starting point:** rather than hand-rolling QEMU, evaluate
[`dockur/windows`](https://github.com/dockur/windows) — it already handles ISO retrieval,
unattended install, a browser VNC UI, and Docker device passthrough, which is most of this
brief. Verify its current USB-passthrough behaviour for a device that **re-enumerates** before
committing; a hand-rolled `qemu-system-x86_64` with `-device qemu-xhci -device usb-host,vendorid=0x0e8d`
is the fallback and gives explicit control over the re-attach behaviour.

Whatever the base: **verify the VID-only passthrough behaviour first, with a trivial USB stick
or the tablet in Android mode, before installing Windows.** Discovering a passthrough limitation
after a 40-minute install is the expensive path.

---

## 7. What to read back, and where it lives

SP Flash Tool's Readback tab wants a **start address** and a **length**, per partition. These
come from `FW/TVE1070M_US_MT8781_A13_WIFI_user_20241016.212541/images/MT6789_Android_scatter.txt`
(`physical_start_addr` and `partition_size`). Full table: `docs/appendix-a-partition-map.md`.

Priority order — grab the first four even if nothing else works:

| Priority | Partition | Start address | Length | Why |
|---|---|---|---|---|
| 1 | `persist` | `0x13208000` | `0x35F8000` (55,264 KiB) | sensor/touch/Wi-Fi calibration; nothing regenerates it |
| 2 | `nvram` | `0x27700000` | `0x4000000` (64 MiB) | Wi-Fi/BT MAC, RF calibration |
| 3 | `nvdata` | `0xA208000` | `0x4000000` (64 MiB) | AP-side NV, Wi-Fi/BT config |
| 4 | `proinfo` | `0x27400000` | `0x300000` (3 MiB) | model, region, **serial number** |
| 5 | `seccfg` | `0x17800000` | `0x800000` (8 MiB) | bootloader lock + dm-verity state |
| 6 | `protect1` | `0x16800000` | `0x800000` | protected NV |
| 7 | `protect2` | `0x17000000` | `0x800000` | protected secure storage |
| 8 | `nvcfg` | `0x8208000` | `0x2000000` (32 MiB) | NV template |
| 9 | `otp` | `0x18000000` | `0x2B00000` (43 MiB) | factory OTP — **dump for the record, never restore** |
| 10 | `metadata` | `0x11208000` | `0x2000000` (32 MiB) | FBE key directory |
| 11 | `frp` | `0x8108000` | `0x100000` (1 MiB) | Factory Reset Protection state |

Deliver the dumps somewhere outside the container, on a mounted volume, e.g.
`backup/readback/<partition>.bin`, and record a `sha256sum` of each plus the tool version.

---

## 8. Verification you can do without the tablet

Do these first; they de-risk the expensive parts:

1. Windows boots, VNC reachable, desktop responsive.
2. `SPFlashToolV6.exe` launches without missing-DLL errors (this is where the VC++ redist issue
   shows up).
3. Device Manager shows the MTK VCOM driver installed and not erroring.
4. USB passthrough survives a **deliberate re-enumeration**: plug in any USB device that
   changes identity (a USB stick is enough), confirm Windows sees detach + re-attach without
   manual intervention.
5. Only then: power-cycle the tablet and attempt Readback of `persist`.

---

## 9. Known risks, and what to do instead

| Risk | Mitigation / fallback |
|---|---|
| QEMU USB passthrough won't re-attach on PID change | pass the whole USB **bus/port** rather than a device filter; or run the VM on a different physical machine with a direct USB port |
| Windows won't install / activate | user supplies ISO and licence; an unactivated Windows runs SP Flash Tool fine for this purpose |
| `/dev/kvm` not usable inside the container | ensure `--device /dev/kvm` and that the container user is in the right group; otherwise expect a very slow but still functional install |
| SP Flash Tool refuses without an Auth file | the vendor package does not obviously ship a separate `.auth`; if it prompts, report back rather than guessing — and note `SLA_Challenge.dll` is present, which is the SLA handshake, not a user-supplied auth file |
| The whole approach is abandoned | the GSI work does **not** depend on it: the no-unlock `Download Only` route never writes `persist`/`nvdata`/`nvram`/`proinfo`/`seccfg`, so the dumps are insurance, not a precondition. See `docs/07-procedure.md` Phase 7 |

---

## 10. Cheaper alternatives worth trying first

The plan above assumes a full Windows VM. That is the highest-confidence route, not necessarily
the cheapest. In rough order of cost, with an honest read on each.

### A. SP Flash Tool **v5 for Linux** — try first, ~15 minutes

MTK's v5 tool has long-standing native Linux builds (v5.1548 … v5.2104 are widely mirrored). No
VM, no driver, no Wine. If it runs, Readback comes free.

The risk is real: this device needs **v6**. The vendor ships `SP_Flash_Tool_V6`, the scatter
declares `MT6789`, and the DA is a V6 artifact. v5 predates that family, so expect
"unsupported platform" or a refusal to parse the V6 DA.

Do it because the failure is fast and unambiguous. If it fails, record the error and stop — do
not spend a day patching an abandoned binary.

### B. mtkclient with the vendor's DA — **already tried; it cannot help**

Worth stating plainly, because it is the intuitive idea. Passing the vendor DA is already a
supported mtkclient argument, and it was used on **every** attempt:

```bash
mtk --loader .../images/download_agent/DA_BR.bin printgpt
```

The DA never gets a chance to matter. mtkclient's sequence is **preloader handshake (`0xA0`) →
crash/exploit → *then* upload the DA**. Every failure we recorded is in step 1, before the DA is
sent. So authenticating, swapping or supplying a different DA cannot fix a handshake that never
completes.

Likewise `SLA_Challenge.dll` is a Windows **PE** DLL, not a plugin file — it is SP Flash Tool's
own implementation of MTK's Secure Link Authentication. There is no interface through which
mtkclient could load it.

### C. Wine / Proton — low probability, but cheap to falsify

The blocker is architectural, not incidental: SP Flash Tool talks to the device through the **MTK
USB VCOM driver**, a Windows **kernel-mode** serial driver. Wine cannot load Windows kernel
drivers, so there is no `COMx` for the tool to open.

Wine 9+ has `wineusb`, which maps some devices to libusb and works for WinUSB-based apps. That
would only help if SPFT could be made to use that path instead of a COM port, which is not how it
is written.

Verdict: ≤30 minutes. Install Wine, run `SPFlashToolV6.exe`, note whether it launches and whether
any device appears. Proton is Wine plus Steam scaffolding and has no advantage here.

### D. Reimplement the SLA handshake — real work, but not absurd

We hold `SLA_Challenge.dll` and a complete firmware package, and this project already has a
reverse-engineering container (REA: Ghidra, radare2, Frida). The DLL is small. If its
challenge/response is self-contained crypto, a Linux implementation of the SLA step could unlock
the readback path without Windows.

Weigh before starting: it is reverse-engineering a security mechanism (on the owner's own
hardware, for backup — say so explicitly rather than glossing it), it is days not hours, and it
only helps **if SLA is what refuses us** — which is unproven. The refusal could equally be the
emergency-download protocol rather than authentication.

### E. Third-party "MTK Auth Bypass" utilities — mentioned for completeness, not recommended

Tools of this class exist and are Windows-only anyway, so they do not avoid the VM. They are
closed-source binaries distributed via GSM forums, commonly bundled with unwanted software, and
they work by defeating a security control. Not appropriate for a device holding the owner's data.

### F. Full Windows VM — the current plan

Highest confidence, highest cost. Chosen because the vendor's own toolchain is known to work with
this DA and this device family, and because the same VM doubles as the recovery path if a later
flash goes wrong.

**Recommendation:** cap A and C at about an hour combined. B is settled, D is a separate project,
E is a non-starter.

---

## 11. What to hand back

1. The working container/compose definition and where the VM disk lives.
2. How to reach the desktop (URL/port), and how to start/stop it.
3. Whether VID-only passthrough with re-enumeration works, and what you had to change.
4. The Readback dumps (or a clear statement of where the chain broke, and at which step).
5. Anything you learned that contradicts §5 — that section is the part most likely to be wrong,
   because it was inferred from host-side observation rather than tested inside a guest.

---

## 12. References in this repo

- `docs/02-firmware-forensics.md` — the AVB chain, key material, partition layout
- `docs/appendix-a-partition-map.md` — all 63 partitions with start addresses and sizes
- `docs/06-backup-and-risk.md` — what each per-unit partition holds and what breaks without it
- `docs/08-findings-log.md` F25–F31 — the full Linux-side failure history this brief exists to escape
- `docs/07-procedure.md` — what happens *after* the dumps exist
