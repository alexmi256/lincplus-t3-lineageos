# Device profile — Lincplus T3

Two kinds of fact are kept separate here: **retail claims** (marketing, reviews) and
**verified on this unit** (`getprop`, the GPT, parsed images). Where they disagree, the
verified value wins, and the disagreement is called out.

## 1. Identity

| | |
|---|---|
| Brand | Lincplus |
| Manufacturer / ODM | **Techvision** (深圳市慧为智能科技, Shenzhen; listed on the Beijing Stock Exchange as 920876) |
| Relationship | **LincPlus is Techvision's own sub-brand**, not a third-party customer — Techvision's own news release describes 慧为旗下子品牌 LincPlus / 子公司 LincPlus (<https://www.techvision.com.cn/News_details/68.html>). There is no separate OEM to escalate to; support goes to the company that wrote the BSP. |
| Retail SKUs | `T3-8G` (8/128, ASIN B0C788XSBN), `T3-6G` (6/128, B0C5ZY1G5W), `T3-FR` (EU box, B0C61SYGQQ) |
| Device / product codename | `T3_US` (`ro.product.device`, `ro.product.model`, `ro.build.product`) |
| Model code (firmware) | `TVE1070M` — from `TVE1070M_US_MT8781_A13_WIFI_user_20241016` |
| Board / platform project | `tb8781p1_64_wifi` |
| SoC | MediaTek **MT8781V/NA** (Helio G99), 2× Cortex-A76 @2.2 GHz + 6× A55 @2.0 GHz, TSMC N6, Mali-G57 MC2 |
| Released | On market Sept 2023; effectively discontinued by mid-2024 |
| Price at launch | $99–$159 |

## 2. Hardware

| Item | Value | Source |
|---|---|---|
| Display | **10.36″ IPS LCD, 2000×1200**, 60 Hz, 10-point touch, 240 dpi | verified: `wm size` → `2000x1200`, `ro.sf.lcd_density=240` |
| Panel orientation | mounted rotated — `ro.surface_flinger.primary_display_orientation=ORIENTATION_270` | verified |
| RAM | **8 GB** LPDDR4X | verified: `MemTotal` = 8,024,024 kB |
| Storage | **128 GB UFS 2.2** | verified — see note below |
| Storage (declared) | 109 GiB `/data` | verified: `df -h /data` |
| Battery | 7000 mAh / 3.8 V claimed; fuel gauge reports `charge_full_design` = **2,940,000 µAh** | **conflict** — see note |
| Charging | 20 W USB-PD/PE+ claimed; 9 V adapter | retail |
| Cameras | 8 MP front, 13 MP rear PDAF + LED | retail |
| Audio | 4 × 1 W speakers, 1 mic, **no 3.5 mm jack** | retail |
| Ports | USB-C (data/audio/OTG), microSD to 1 TB | retail |
| Wi-Fi / BT | Wi-Fi 5 (2.4/5 GHz), BT 5.2 | retail; vendor: combo chip `mt6631_6635` |
| GNSS | GPS/BeiDou/GLONASS/Galileo | retail; `ro.vendor.mtk_gps_support=1` |
| Sensors | accel, light, proximity | **verified** — 7 HAL sensors, see note |
| Cellular | **none** — Wi-Fi-only SKU, no modem, no SIM | verified |
| Dimensions / weight | 249 × 159 × 7.9 mm; weight quoted as 460 / 480 / 490 g in different sources | retail |
| DRM | Widevine L1 (HD streaming claimed by reviews) | retail + `android.hardware.drm@1.4-service.widevine` present |

### Note — storage is UFS, not eMMC

The scatter file's first section says `storage_type: EMMC` and `ro.vendor.mtk_emmc_support=1`
is set, which is misleading (MTK scatters carry both layouts; the flasher picks one).
Verified UFS: `ro.boot.boot_devices = bootdevice,soc/11270000.ufshci`, a
`11270000.ufshci` platform device exposing UFS `device_descriptor`/`geometry_descriptor`/
`health_descriptor`, and SCSI-style block names (`sda`/`sdb`/`sdc`) rather than `mmcblk0`.
UL's PCMark measured 896 MB/s read. Full reasoning in `02-firmware-forensics.md` §5.1.

### Note — battery figure does not match

Marketing says 7000 mAh; the fuel gauge reports a 2.94 Ah design capacity, and a 100% charge
counter of 2.946 Ah. That is not a rounding difference. Either the gauge is misconfigured for
this pack or the marketing number is wrong. **Treat the gauge as what Android will report**,
and do not expect any software change to alter runtime.

### Note — no gyroscope, no compass, no magnetometer

UL's listing mentions "Compass", but the device enumerates exactly 7 sensors and none of them
are magnetic:

| Sensor | Chip |
|---|---|
| accelerometer | `stk83xx_acc` (Sensortek) |
| light (ALS) | `stk3x3x_als` |
| proximity | `stk3x3x_ps` |
| significant motion, tilt, device orientation, uncalibrated accel | MTK virtual |

So: no compass in Maps, no gyro-based gaming, no AR. No GSI can add these.

## 3. Software as shipped

| | |
|---|---|
| Android | 13, build `TP1A.220624.014`, incremental `20241016` |
| Security patch | **2024-09-05** |
| Build date | 2024-10-16 |
| Vendor | Android **12** BSP, `ro.vendor.api_level=31`, `SP1A.210812.016` |
| Kernel | `5.10.209-android12` |
| Bootloader | `tb8781p1_64_wifi_8c8e89655_20241016125` |
| Packages | 210 total, 85 Google (`com.google.android.gms`, `com.android.vending`) — **GMS build** |
| OEM apps | exactly one: `cn.com.techvision.sound` |
| System origin | **Google GSI** (`gsi_arm64/generic_arm64`, `SGR1.240502.001.B3`) — see `02-firmware-forensics.md` §2 |

Update history: shipped with a 2023-04 patch, one known OTA to 2024-10-16 / 2024-09-05.
That is it. No Android 14 build exists anywhere; the tablet was never advertised for one.

## 4. Firmware and GPL

- **One known public build**: `TVE1070M_US_MT8781_A13_WIFI_user_20241016`. Nothing on Needrom,
  Halabtech, GSMmafia, or any firmware aggregator.
- The package the owner has here is the one Lincplus support supplied to an XDA member
  (<https://xdaforums.com/t/firmware-tablet-lincplus-t3.4736040/>); that thread is the only
  substantive T3 thread anywhere.
- **Kernel source is not published.** No kernel tarball, no "open source" page on
  lincplustech.com or techvision.com.cn, no GitHub repo. That is a GPLv2 §3 violation for a
  shipping Linux kernel. The lever is a written request to `support@lincplustech.com` citing
  GPLv2 §3 and the exact build string — they did respond to a firmware request once.
  **Without kernel source there can be no custom ROM, only a GSI.** This is the single
  constraint that decides the whole project's shape.
- LincPlus has scrubbed the tablet line: the store lists one tablet, sold out, and the
  downloads page carries no tablet firmware at all
  (<https://store.lincplustech.com/collections/all>).

## 5. Sibling devices — where to look for help

The T3 has essentially **zero** development community. The useful knowledge lives on sibling
hardware. Ranked by practical value:

| Device | Why it matters |
|---|---|
| **Alldocube iPlay 50 Pro / 60 mini Pro** — Helio G99, 10.4″ 2000×1200, 8/128 UFS 2.2 | Best-documented G99 tablet: unlock guides, GSI flashing reports, LineageOS/crDroid threads. An XDA user already **cross-flashed iPlay 50 Pro firmware onto a T3** with SP Flash Tool (it flashed cleanly; it did not revive his dead unit, but it proves the firmware path). |
| **Primebook 2 / 2 Pro** (India) — Helio G99, Android 15 | A Geekbench entry for a Primebook reports board string **`tb8781p1_64_wifi`** — the same board string as this tablet. If that holds, an **Android 15 BSP for this exact board exists**, which is the most valuable single lead for a future vendor upgrade. Treat as probable, not confirmed. |
| **Acer ACTAB1225E / ATAB1225E** — 11.97″ 2000×1200, Android 14, MT8781V/NA | An Android 14 build on the same SoC; candidate donor for newer vendor blobs. Board string unverified. |
| **Lenovo Tab P11 2nd Gen (TB350XU)** — MT6789 | Same SoC generation; its Widevine L1→L3-after-flash report is the best analogue for the DRM risk. |

Community status, briefly: one XDA firmware thread, no device forum, no TWRP, no device tree,
no LineageOS thread, nothing on 4PDA, nothing on GitHub, no Telegram channel. One XDA member
claims to have run **crDroid** on a T3 — unverified, no build name, no logs, but it is the only
direct claim that a modern system image has booted on this hardware.

**Practical consequence:** everything here is bootstrapped from generic MT8781/Helio-G99
knowledge (mtkclient, SP Flash Tool, AVB flags, arm64 GSI), not from device-specific work.
