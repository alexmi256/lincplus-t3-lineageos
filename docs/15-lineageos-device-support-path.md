# What it would take to get this tablet officially supported by LineageOS

Researched 2026-11-14 against the primary sources:
`wiki.lineageos.org/submitting_device.html`, `wiki.lineageos.org/device_requests.html`, and
`github.com/LineageOS/charter/blob/main/device-support-requirements.md`.

## 1. The official process

From the wiki, verbatim in structure:

1. **Meet the prerequisites.** The device MUST satisfy the charter's device support requirements.
   Exceptions are possible but must be requested individually and approved by **no fewer than 3
   Project Directors**.
2. **Be a maintainer.** "LineageOS is not a 'submit it and forget it' home." You must commit to
   fixing bugs, applying security updates and improving performance indefinitely.
3. **Submit.** Email devrel with GitHub links to **device, vendor and kernel trees**, plus the email
   addresses of every maintainer. Review of source and vendor blobs follows; changes may be
   requested before resubmission. Not all requests are accepted.
4. **If accepted:** add the device to the wiki, add it to `lineage_build_targets`, get access to
   internal tooling, and ship weekly builds.

And from `device_requests.html`: support is **not** driven by how many people ask. "The folks who
maintain devices for LineageOS choose devices that interest them… LineageOS is not a corporation
with employees." A device becomes official when a developer does the work and hands it over.

## 2. The requirements that actually bite

Selected charter clauses with direct bearing on this tablet:

| Area | Requirement |
|---|---|
| Ownership | Maintainer MUST own the device or a variant |
| Kernel | **Non-GKI devices MUST NOT ship a prebuilt kernel.** GKI devices MAY use a prebuilt GKI image from Google, but **MUST build all feasible modules from source** |
| Device tree | Unique codename; `lineage_<device>.mk`; valid `lineage.dependencies`; nothing from outside the LineageOS org in it |
| Build type | MUST be `userdebug` |
| SELinux | MUST be enforcing |
| Verity | MUST disable verity on system for userdebug; SHOULD keep it on vendor |
| Encryption | MUST support hardware-backed encryption if stock did; MUST support software encryption |
| Vendor image | MUST NOT require a modified prebuilt vendor image; A/B devices must either build vendor or document firmware install + slot parity |
| Blobs | MUST ship a working proprietary-files extraction script reproducing the exact binaries |
| Hardware | Audio, Wi-Fi (same MAC as stock), BT (same MAC), camera front+rear, video recording, codecs, display, sensors, MTP — all MUST work if stock had them |
| Play Integrity | MUST NOT alter validation responses |
| Stability | No screen-of-death, no abnormal battery drain |

## 3. Our device's actual position

**Confirmed GKI 2.0** — measured on the running tablet:

```
kernel: Linux version 5.10.209-android12-9-00016-g7c6bbcca33e1-ab12029497
ro.kernel.version=5.10        ro.board.platform=mt6789        ro.vendor.api_level=31
/vendor/lib/modules: 171 modules (.ko)
```

plus `init_boot_a/b` and `vendor_dlkm_a` in the scatter — the Android 13+ GKI boot layout.

This matters a lot: **the "no prebuilt kernel" rule does not apply to GKI devices.** In principle a
port could ship Google's GKI `boot.img` and keep the OEM vendor module set. But the charter adds
"MUST build all feasible modules from source", and there are 171 vendor modules here whose source
MediaTek does not publish. That is the clause an exception would have to address.

### Status against the prerequisites

| Requirement | Status |
|---|---|
| Device owned | ✅ two units |
| Bootloader unlockable, A/B, dynamic super | ✅ proven |
| GKI kernel, prebuilt acceptable | ✅ (with module caveat) |
| Hardware runs Android 15 at all | ✅ our GSI boots, L1, GApps |
| Device tree | ❌ does not exist anywhere |
| Vendor blobs extraction tree | ❌ would have to be written |
| Kernel source from OEM | ❌ not published (GPLv2 §3 violation) |
| Community / co-maintainers | ❌ zero |
| Full hardware validation (camera, sensors, MACs) | ❓ unverified |

**The hard blocker is not the kernel — it is that no device tree exists and nobody has written one.**
A port is not "adapt the GSI"; it is a from-scratch bring-up: `device.mk`, `BoardConfig.mk`, fstab,
init scripts, sepolicy, overlays, HAL packaging, `vendor_boot`/`init_boot` handling, recovery, OTA.

## 4. Realistic effort

Nothing about this hardware is exotic for Treble — the vendor partition is intact and a GSI already
boots — which removes the hardest part of a traditional port (HAL bring-up from scratch). What
remains is still substantial:

- **Weeks of work** to get a booting, mostly-functional device tree for someone experienced with
  LineageOS device trees; **months** for a first-timer, which is the wiki's own framing
  ("weeks (months?) of hard work").
- Camera is usually the long tail: MTK camera HALs are among the least cooperative.
- Every charter item has to be *verified*, not assumed — MAC stability across reboots, hardware FBE,
  sensor fusion, codec coverage.
- Then ongoing monthly maintenance, forever, by whoever wrote it.

And devrel still may decline: a single-maintainer, single-user device with no community and an
unpublished kernel is a weak submission even if it builds.

## 5. The honest recommendation

Three paths, ordered by value per unit of effort:

1. **Stay on the GSI (current state).** It delivers Android 15, release-keys, Widevine L1, GApps and
   17 months of security patches. A device tree would mostly reproduce this with more risk.
2. **Write an *unofficial* device tree**, published on GitHub, without seeking LineageOS approval.
   That is the normal route for devices like this, and it needs no exception from anyone. But it is
   still the same weeks of bring-up work.
3. **Ask LincPlus for the kernel source** under GPLv2 §3, citing the exact build string
   (`TVE1070M_US_MT8781_A13_WIFI_user_20241016`). They have responded to a firmware request before.
   This is cheap to try and would materially improve any future port — a source-built kernel plus
   module build removes the charter exception and the GPL problem at once.

Recommended order: **3 as a cheap parallel action, 1 as the working solution, 2 only if someone
actually wants to own a device tree long-term.**

## 6. If a port were attempted, concrete first steps

1. Dump stock and keep a clean `vendor`/`odm` reference (already have readbacks).
2. Create `device/lincplus/T3_US` with `lineage_T3_US.mk`, `BoardConfig.mk`, `device.mk`, fstab from
   the stock `vendor/etc/fstab.*`.
3. Run `extract-utils` against a stock image to generate `vendor/lincplus/T3_US` (proprietary blobs).
4. Reuse the Google GKI `boot.img` matching KMI `android12-5.10`, keep `vendor_dlkm` from OEM.
5. Bring up incrementally: display → audio → Wi-Fi/BT → sensors → camera → encryption → OTA.
6. Validate every charter item explicitly, then decide whether to submit.

Codenames are free-form as long as they are unique; `T3_US` is fine but a lowercase codename
(`lincplus_t3`) matches LineageOS convention better.
