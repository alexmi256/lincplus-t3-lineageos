# Appendix A — Partition map (MediaTek MT6789 / tb8781p1, UFS)

Generated directly from `MT6789_Android_scatter.txt` in the OEM firmware package by
`work/tools/scatter2md.py`. Sizes are the *declared* partition sizes (`partition_size`),
not the size of the image that gets written into them — many partitions are far larger than
their contents (e.g. `boot_a` is 64 MiB but only holds a 21 MB image).

> The table below is generated from the **EMMC** section of the scatter file, because that is
> the section whose `pname`/size fields are complete. The device actually has **UFS 2.2**
> storage (see `docs/02-firmware-forensics.md` §5.1); the same file contains a parallel UFS
> section with identical partition names, sizes and ordering, differing only in `region`
> (`UFS_LU0`, `UFS_LU2`, …) and `boot_channel: UFSHCI_0`. For flashing purposes the two are
> interchangeable; treat the numbers here as authoritative for both.

`Region` is the storage area: the boot partitions (`EMMC_BOOT1/Boot2`, or `UFS_LU0/LU1`) hold
the preloader and are invisible to the normal partition table; `EMMC_USER`/`UFS_LU2` is the
main user area.

`Op` is MTK's operation type: `BOOTLOADERS` (boot chain), `UPDATE` (normal flashable),
`INVISIBLE` (flash tool leaves it alone), `PROTECTED` (factory data, protected from
normal flashing), `NEEDRESIZE` (resized on first boot), `RESERVED`, `BINREGION`.

⚠️ **Know which SP Flash Tool mode you are in.** They are not interchangeable:

| Mode | Behaviour | Use it? |
|---|---|---|
| **Download Only** | writes *only* the partitions you tick. Touches nothing else. | ✅ yes — this is what Phase 7 uses, and the only mode safe enough to try a GSI |
| **Firmware Upgrade** | rewrites the partition table and downloads every image in the scatter; at minimum it wipes `userdata`. This is what the vendor's own PDF recommends for a full restore | ⚠️ only for a deliberate back-to-stock, never for an experiment |
| **Format All + Download** | erases the whole flash including factory/calibration areas before writing | ❌ **never**. This is the documented Widevine-L1 killer (see `06-backup-and-risk.md`) |

Because `Firmware Upgrade` repartitions, it may also rewrite partitions that carry no image in
the package (`persist`, `nvdata`, `nvram`, `proinfo`, `protect1/2`, `seccfg`, `otp`, `expdb`) —
and those are exactly the per-unit ones with no copy anywhere else. Whatever mode you use,
have your dumps first. `Download Only` avoids the question entirely.

---

| # | Partition | Size | Size (bytes) | Image in package | Region | Op | Download |
|---|---|---|---|---|---|---|---|
| 0 | `preloader` | 1 MiB | 0x100000 | `preloader_tb8781p1_64_wifi.bin` | EMMC_BOOT1 | BOOTLOADERS | true |
| 1 | `preloader_backup` | 1 MiB | 0x100000 | `preloader_tb8781p1_64_wifi.bin` | EMMC_BOOT2 | BOOTLOADERS | true |
| 2 | `pgpt` | 32 KiB | 0x8000 | — | EMMC_USER | INVISIBLE | false |
| 3 | `misc` | 512 KiB | 0x80000 | — | EMMC_USER | INVISIBLE | false |
| 4 | `para` | 512 KiB | 0x80000 | — | EMMC_USER | INVISIBLE | false |
| 5 | `expdb` | 128 MiB | 0x8000000 | — | EMMC_USER | INVISIBLE | false |
| 6 | `frp` | 1 MiB | 0x100000 | — | EMMC_USER | INVISIBLE | false |
| 7 | `nvcfg` | 32 MiB | 0x2000000 | — | EMMC_USER | PROTECTED | false |
| 8 | `nvdata` | 64 MiB | 0x4000000 | — | EMMC_USER | INVISIBLE | false |
| 9 | `vbmeta_a` | 8 MiB | 0x800000 | `vbmeta.img` | EMMC_USER | UPDATE | true |
| 10 | `vbmeta_system_a` | 8 MiB | 0x800000 | `vbmeta_system.img` | EMMC_USER | UPDATE | true |
| 11 | `vbmeta_vendor_a` | 8 MiB | 0x800000 | `vbmeta_vendor.img` | EMMC_USER | UPDATE | true |
| 12 | `vbmeta_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 13 | `vbmeta_system_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 14 | `vbmeta_vendor_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 15 | `metadata` | 32 MiB | 0x2000000 | — | EMMC_USER | INVISIBLE | false |
| 16 | `persist` | 55264 KiB | 0x35f8000 | — | EMMC_USER | PROTECTED | false |
| 17 | `protect1` | 8 MiB | 0x800000 | — | EMMC_USER | PROTECTED | false |
| 18 | `protect2` | 8 MiB | 0x800000 | — | EMMC_USER | PROTECTED | false |
| 19 | `seccfg` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 20 | `otp` | 43 MiB | 0x2b00000 | — | EMMC_USER | INVISIBLE | false |
| 21 | `spmfw_a` | 1 MiB | 0x100000 | `spmfw.img` | EMMC_USER | UPDATE | true |
| 22 | `pi_img_a` | 1 MiB | 0x100000 | `pi_img.img` | EMMC_USER | UPDATE | true |
| 23 | `dpm_a` | 4 MiB | 0x400000 | `dpm.img` | EMMC_USER | UPDATE | true |
| 24 | `scp_a` | 6 MiB | 0x600000 | `scp.img` | EMMC_USER | UPDATE | true |
| 25 | `sspm_a` | 1 MiB | 0x100000 | `sspm.img` | EMMC_USER | UPDATE | true |
| 26 | `mcupm_a` | 1 MiB | 0x100000 | `mcupm.img` | EMMC_USER | UPDATE | true |
| 27 | `gz_a` | 32 MiB | 0x2000000 | `gz.img` | EMMC_USER | UPDATE | true |
| 28 | `lk_a` | 4 MiB | 0x400000 | `lk.img` | EMMC_USER | UPDATE | true |
| 29 | `boot_a` | 64 MiB | 0x4000000 | `boot.img` | EMMC_USER | UPDATE | true |
| 30 | `vendor_boot_a` | 64 MiB | 0x4000000 | `vendor_boot.img` | EMMC_USER | UPDATE | true |
| 31 | `init_boot_a` | 8 MiB | 0x800000 | — | EMMC_USER | UPDATE | false |
| 32 | `dtbo_a` | 8 MiB | 0x800000 | `dtbo.img` | EMMC_USER | UPDATE | true |
| 33 | `tee_a` | 5 MiB | 0x500000 | `tee.img` | EMMC_USER | UPDATE | true |
| 34 | `sec1` | 2 MiB | 0x200000 | — | EMMC_USER | INVISIBLE | false |
| 35 | `proinfo` | 3 MiB | 0x300000 | — | EMMC_USER | PROTECTED | false |
| 36 | `nvram` | 64 MiB | 0x4000000 | — | EMMC_USER | BINREGION | false |
| 37 | `boot_para` | 1 MiB | 0x100000 | — | EMMC_USER | INVISIBLE | false |
| 38 | `dram_para` | 25 MiB | 0x1900000 | — | EMMC_USER | INVISIBLE | false |
| 39 | `connsys_bt_a` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 40 | `connsys_wifi_a` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 41 | `connsys_gnss_a` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 42 | `logo` | 24 MiB | 0x1800000 | `logo.bin` | EMMC_USER | UPDATE | true |
| 43 | `spmfw_b` | 1 MiB | 0x100000 | — | EMMC_USER | INVISIBLE | false |
| 44 | `pi_img_b` | 1 MiB | 0x100000 | — | EMMC_USER | INVISIBLE | false |
| 45 | `dpm_b` | 4 MiB | 0x400000 | — | EMMC_USER | INVISIBLE | false |
| 46 | `scp_b` | 6 MiB | 0x600000 | — | EMMC_USER | INVISIBLE | false |
| 47 | `sspm_b` | 1 MiB | 0x100000 | — | EMMC_USER | INVISIBLE | false |
| 48 | `mcupm_b` | 1 MiB | 0x100000 | — | EMMC_USER | INVISIBLE | false |
| 49 | `gz_b` | 32 MiB | 0x2000000 | — | EMMC_USER | INVISIBLE | false |
| 50 | `lk_b` | 4 MiB | 0x400000 | — | EMMC_USER | INVISIBLE | false |
| 51 | `boot_b` | 64 MiB | 0x4000000 | — | EMMC_USER | INVISIBLE | false |
| 52 | `vendor_boot_b` | 64 MiB | 0x4000000 | — | EMMC_USER | INVISIBLE | false |
| 53 | `init_boot_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 54 | `connsys_bt_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 55 | `connsys_wifi_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 56 | `connsys_gnss_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 57 | `dtbo_b` | 8 MiB | 0x800000 | — | EMMC_USER | INVISIBLE | false |
| 58 | `tee_b` | 5 MiB | 0x500000 | — | EMMC_USER | INVISIBLE | false |
| 59 | `super` | 9 GiB | 0x240000000 | `super.img` | EMMC_USER | UPDATE | true |
| 60 | `userdata` | 3 GiB | 0xc0000000 | `userdata.img` | EMMC_USER | NEEDRESIZE | true |
| 61 | `flashinfo` | (reserved) | | | EMMC_USER | RESERVED | false |
| 62 | `sgpt` | (reserved) | | | EMMC_USER | RESERVED | false |

---

## Partitions that are per-unit and have no image in the package

These are absent from `images/` and therefore cannot be restored from the OEM release:

`pgpt`, `misc`, `para`, `expdb`, `frp`, `nvcfg`, `nvdata`, `metadata`, `persist`,
`protect1`, `protect2`, `seccfg`, `otp`, `sec1`, `proinfo`, `nvram`, `boot_para`,
`dram_para`, `connsys_bt_a/b`, `connsys_wifi_a/b`, `connsys_gnss_a/b`, `init_boot_a/b`,
`vbmeta_b`, `vbmeta_system_b`, `vbmeta_vendor_b`, and every `_b` slot of `spmfw`, `pi_img`,
`dpm`, `scp`, `sspm`, `mcupm`, `gz`, `lk`, `boot`, `vendor_boot`, `dtbo`, `tee`.

The `connsys_*` ones are interesting: they are populated at runtime by the Wi-Fi/BT/GNSS
firmware loader from `/vendor/firmware`, so they regenerate — but their MAC addresses and
calibration do not. `dram_para` and `boot_para` are produced by the preloader on first boot.
