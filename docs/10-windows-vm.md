# Windows VM — built, and where it stands

Answer to `09-windows-vm-brief.md` §11. The working stack lives outside this
repository, in **`/opt/data/projects/mtk-win-vm/`** (it contains a 40 GB VM disk,
a 6 GB Windows ISO and the vendor binaries, none of which belong in git). Its
`README.md` is the operating manual; this file is the handback.

## 1. The container, and where the disk lives

`dockur/windows` (v6.06 image) with QEMU 11.1.1, Windows 10 Pro 19045 installed
unattended, driven by `/opt/data/projects/mtk-win-vm/compose.yml`.

| | |
|---|---|
| VM disk | `mtk-win-vm/storage/data.img` — 40 GB sparse, 11 GB used |
| Windows ISO | `mtk-win-vm/storage/win10x64.iso` (downloaded from Microsoft's servers by dockur) |
| Provisioning | `mtk-win-vm/oem/` → `C:\OEM`, `install.bat` → `provision.ps1` |
| Tool + scatter + DA | `mtk-win-vm/shared/mtk/` → `\\host.lan\Data\mtk` → `C:\MTK` |

Start/stop is a normal compose lifecycle: `docker compose up -d` / `down` in that
directory (`restart: unless-stopped` means it comes back with Docker). Install to
desktop took ≈12 minutes on this host; a restart is a boot.

## 2. Reaching the desktop

- **Browser VNC:** `http://<host>:8006` (noVNC; no client needed, works on a headless box).
- **RDP:** `<host>:3389`, user `Docker`, password `<set via WIN_PASS>` (change via `WIN_USER`/`WIN_PASS` in `.env` before first install).
- **Shell (the useful one):** `python3 tools/guest.py run "…"` — OpenSSH inside
  the guest, key at `mtk-win-vm/oem/ssh/id_ed25519`, no RDP session required.
- **Agent eyes/hands:** `python3 tools/qmp.py shot|click|key|usb` — QEMU-level
  screenshots and input, available even before Windows finishes booting.

## 3. USB passthrough with re-enumeration

Worked as the brief hoped, with one correction and one caveat.

- **Correct as written:** pass by vendor ID only. The filter is
  `-device usb-host,vendorid=0x0e8d` inside `ARGUMENTS`, plus
  `privileged: true` and `devices: [/dev/bus/usb]`. Nothing else was needed — no
  udev rules, no `cdc_acm` blacklist on the host.
- **Verified here:** with the tablet in Android mode (`0e8d:201c`), QEMU attached
  it to the VM and Windows enumerated it as `USB\VID_0E8D&PID_201C`
  (Android ADB Interface). So the filter is not pinned to one PID, and delivery
  survives into the guest.
- **New caveat (brief §5 assumption corrected):** QEMU's `usb-host` re-scans the
  bus **every 2 s** (`usb_host_auto_check` in `hw/usb/host-libusb.c`), and the
  preloader window is 2–4 s. A power-cycle can therefore be *missed*, and after
  three failed opens QEMU stops retrying that filter until the device disappears
  again. Practically: **start SP Flash Tool first**, then power-cycle the
  tablet, and expect to retry. "The device must be attached before powering the
  tablet on" is not the constraint; the tool enumerating COM ports once at start
  is.
- **Still unproven:** the live Android→preloader→VCOM transition inside the
  guest. It needs a hand on the hardware (hold Vol+ while powering on). The
  driver INF covers `USB\Vid_0e8d&Pid_2000` and is installed, so binding should
  be automatic; that is the one step left.

## 4. Readback dumps

**Not yet taken** — that is the hardware step above. The chain up to the moment
the preloader appears is built and proven, and the readback itself is a command:

```bash
cd /opt/data/projects/mtk-win-vm
python3 tools/readback.py --partitions persist --wait 60     # then power-cycle the tablet
python3 tools/readback.py --all                              # remaining 10 partitions
```

Dumps land in `mtk-win-vm/backup/*.bin` with a sha256 per file, and `persist` is
checked for `53 EF` at `0x438` automatically.

Two things make this more than a GUI automation exercise:

- **SP Flash Tool v6 has a console mode.** `SPFlashToolV6.exe -i config.xml`,
  validated against the `console_mode.xsd` that ships next to the exe, with
  `READ-FLASH` / `READ-PARTITION` commands. Verified on this build
  (v6.2208.00): it accepts the generated XML, prints `XML schema validation
  passed!` → `scan device START.` and waits for the port. `tools/gen_console_xml.py`
  builds that XML from the scatter/partition table and validates it before use.
- **SPFT v6 is a 32-bit binary.** It needs the **x86** VC++ redistributable; with
  only the x64 one it exits instantly with `STATUS_DLL_NOT_FOUND` (0xC0000135)
  and prints nothing at all. Both are installed by `provision.ps1`.

Also worth recording: the vendor `Tool/MTK-Driver-v5.2307/MTK Driver Setup.exe`
is an Inno Setup wrapper. `innoextract` yields `app/drv/CDC/cdc-acm.inf` +
`usb2ser.sys`, whose hardware IDs cover BROM `0003`, **preloader `2000`**, DA
`2001`, `2007`, META `200E`. `pnputil /add-driver cdc-acm.inf /install` is the
whole "driver install" — no GUI, no test-signing.

## 5. Where the chain could still break

In order of likelihood, with the check that distinguishes each:

| Break point | Symptom | Check |
|---|---|---|
| Preloader window missed by the 2 s USB poll | No new device in the guest after a power-cycle | `tools/qmp.py usb` — if it never lists a `0e8d` device, QEMU never saw it |
| Windows binds no driver in time | Device appears in QEMU but no COM port | `Get-CimInstance Win32_PnPEntity \| ? Name -match COM` in the guest |
| DA/SLA authentication refused | Port exists, SPFT reports handshake failure | Console output; `-a auth_file.auth` exists as the place to supply one, but no `.auth` ships |
| SPFT needs an interactive session | console mode exits or prints nothing | Run it over SSH first; if it misbehaves, `tools/probes/run-spft-ssh.ps1` shows the session-1 variant via a scheduled task |

Full detail, per-layer troubleshooting and the operating sequence:
`mtk-win-vm/docs/02-readback.md`; evidence for every claim above:
`mtk-win-vm/docs/03-verification.md` and `mtk-win-vm/docs/evidence/`.
