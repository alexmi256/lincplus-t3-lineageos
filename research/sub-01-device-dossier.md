# LincPlus T3 (T3_US / TVE1070M) — Sourced Specification & Device-Identity Dossier

Compiled 2026-11-12. Every non-obvious claim carries a URL. Items I could not verify are marked **[UNVERIFIED]**; inferences are marked **[SPECULATION]**.

---

## 1. Retail specification

| Item | Value | Source |
|---|---|---|
| Brand / model | LincPlus T3 (SKUs: T3-6G, T3-8G, T3-FR) | Amazon listings below |
| Display | 10.36″ IPS LCD, 2000×1200, 60 Hz, in-cell, 10-point touch, ~300–330 nits, 1B colours | https://manuals.plus/lincplus/t3-android-13-tablets-manual ; https://www.fabionieddu.com/lincplus-t3-tablet-android-13-recensione/ ; https://techinspection.net/lincplus-t3-tablet-review/ |
| SoC | MediaTek Helio G99 (MT8781), TSMC N6, 2× Cortex-A76 @2.2 GHz + 6× A55 @2.0 GHz | https://www.mediatek.com/products/smartphones/mediatek-helio-g99 ; manual table "CPU MediaTek MT8781" |
| GPU | Arm Mali-G57 MC2 | https://www.fabionieddu.com/lincplus-t3-tablet-android-13-recensione/ ; https://benchmarks.ul.com/hardware/tablet/LincPlus+T3+review |
| RAM | 8 GB LPDDR4/LPDDR4X (early units); 6 GB variant sold from ~2024 | https://manuals.plus/asin/B0C788XSBN ; https://www.amazon.com/LincPlus-10-4inchs-Android-Tablets-Computer/dp/B0C5ZY1G5W |
| Storage | 128 GB UFS 2.2, microSD to 1 TB | https://www.amazon.com/LincPlus-Octa-Core-Processor-Expandable-T3-8G/dp/B0C788XSBN ; https://www.newegg.com/p/0EJ-02B5-00005 |
| Storage speed (measured) | PCMark Storage 2.0: 896 MB/s seq read, 233 MB/s seq write (UFS-class, not eMMC) | https://benchmarks.ul.com/hardware/tablet/LincPlus+T3+review |
| Battery | 7000 mAh / 3.8 V (26.6 Wh), ~8 h video | manual (above) |
| Charging | 20 W, USB-PD + PE+; 9 V USB-C adapter supplied | manual (above); charger listing https://www.amazon.com/Adapter-Charging-LincPlus-TVE1070-Android/dp/B0FQV7Z4DP |
| Cameras | Front 8 MP; rear 13 MP PDAF + LED flash | manual (above) |
| Audio | 4× 1 W "box" speakers, 1× mic, **no 3.5 mm jack** | manual; https://www.fabionieddu.com/lincplus-t3-tablet-android-13-recensione/ |
| Ports | USB-C (data + audio-out + OTG), microSD tray, pogo/keyboard: none documented | manual |
| Wi-Fi / BT | Wi-Fi 5 (802.11 a/b/g/n/ac, 2.4/5 GHz), Bluetooth 5.2 | manual; https://www.amazon.com.be/-/en/LincPlus-Android-Expansion-7000mAh-Battery/dp/B0C61SYGQQ |
| GNSS | GPS / BeiDou / GLONASS / Galileo | manual |
| Sensors | G-sensor, light sensor, proximity (no gyro/compass listed; UL lists "Compass" — conflicting) | manual vs https://benchmarks.ul.com/hardware/tablet/LincPlus+T3+review |
| DRM | Widevine L1 (Netflix/Prime HD claimed) | https://www.reddit.com/r/androidtablets/comments/18nwcoz/lincplus_t3_is_incredible_for/ |
| Stylus | Advertised "touchscreen with stylus support"; WGP-protocol active pen sold separately; some bundles ship "with Pen" | https://manuals.plus/asin/B0C788XSBN ; https://www.amazon.com/LincPlus-Octa-Core-Processor-Expandable-T3-8G/dp/B0C788XSBN |
| Dimensions | 249 × 159 × 7.9 mm, 8.8 mm bezel | manual; UL |
| Weight | **Conflicting: 460 g** (UL, Amazon copy, manuals.plus ASIN page) vs **480 g** (printed manual spec table) vs **490 g** (eBay seller) | UL; manual; https://www.ebay.com/itm/397976087606 |
| Body | Full metal, grey | manual |
| OS at launch | Android 13, near-stock (Google apps only), April 2023 security patch | https://www.fabionieddu.com/lincplus-t3-tablet-android-13-recensione/ |
| Price | $99–$159 street; camel³ 3rd-party new $89.90–$159.00 (avg $108.89), used $59–$85 | https://camelcamelcamel.com/product/B0C5ZY1G5W |
| Release | On market by **Sept 2023** (review 2023-09-21; Amazon ASIN B0C5ZY1G5W); effectively **discontinued by mid-2024** | https://techinspection.net/lincplus-t3-tablet-review/ ; https://www.reddit.com/r/androidtablets/comments/1def2l4/been_looking_for_lincplus_t3_for_months_now_but/ |
| Warranty | 2 years + 30-day return (vendor claim) | https://manuals.plus/asin/B0C788XSBN |

Notes: the printed manual's storage row reads "128G eMMC/UFS+DDR" (ambiguous), but retail copy, reviews and the 896 MB/s benchmark all support UFS 2.2. Treat eMMC as wrong.

---

## 2. Model codes, variants, firmware builds

**Identity strings**
- Retail SKUs: `T3-6G` (6/128), `T3-8G` (8/128), `T3-FR` (EU/French box). ASINs: B0C788XSBN (T3-8G), B0C5ZY1G5W (T3-6G), B0C61SYGQQ (T3-FR).
- Codename reported by Google Play / game device lists: **`Lincplus T3_US`** (alongside `LincPlus M8_EU`, `LincPlus M11_EU`) — https://www.reddit.com/r/androidtablets/comments/1c29eeg/thoughts_on_these_three_tablets/ (snippet of The Division Resurgence device list). Consistent with your `T3_US`.
- Firmware package name: `TVE1070M_US_MT8781_A13_WIFI_user_20241016` (region US, WiFi-only, A13, build 2024-10-16).
- `ro.product.device` = `tb8781p1_64_wifi`; ALPS branch string `alps-mp-s0.mp1.rc-V15.175_techvision.s0mp1rc.tb8786p1.64_P3`.

**Build-string observation (relevant to porting):** the ALPS branch is named for **`tb8786p1.64`** (MT8786 platform) while the product/device is `tb8781p1_64_wifi` (MT8781). This is normal for MediaTek "same-family" projects where the BSP started from the MT8786 reference and was re-targeted to MT8781. **[SPECULATION]** on the derivation; the string difference itself is a hard fact from your dump and should be assumed to explain any mismatch when matching sibling firmware.

**Known firmware builds:** exactly **one** publicly evidenced build — `..._user_20241016` (patch level 2024-09-05). Shipping firmware was Android 13 with **April 2023** patch (review, May 2024), so at least one OTA landed between mid-2023 and Oct 2024. No `TVE1070M` build appears on Needrom, Halabtech, GSMmafia or any firmware aggregator (searched; zero hits). No EU/global variant build string found. **[UNVERIFIED]** whether an Android 14 build exists — none found anywhere; the T3 was never advertised for A14 (the T4/M8/M11 are the A14-generation products).

**Only known public ROM artifact:** XDA user *TheMrSlime* obtained the official ROM **from LincPlus support** and shared `Copia de T3-US.rar` on Google Drive — https://drive.google.com/file/d/1jUlYesGqmdOWVlbZQlICFi5giyFRt8zy/view (live, "too large to preview", contains flash instructions, needs a PC). Thread: https://xdaforums.com/t/firmware-tablet-lincplus-t3.4736040/

---

## 3. The ODM: Techvision — and it is also the brand owner

- **Techvision Intelligent Technology Co., Ltd** (深圳市慧为智能科技股份有限公司), founded 2011-05-25, HQ Shenzhen (Nanshan, TCL International E-City), ~150 R&D engineers, ~500 staff; **listed on the Beijing Stock Exchange** (NEEQ 832876 → BSE **920876**); IDH/ODM across Intel, Rockchip and MediaTek platforms; product lines include tablets, 2-in-1s, notebooks, rugged/industrial terminals, NAS, conferencing gear. Sources: https://en.wulu.com/supplier/details/403a423427fb4780a79d6da1a0a82a10 ; https://www.techvision.com.cn/
- **LincPlus is Techvision's own sub-brand/subsidiary**, not an independent customer: Techvision's own news release states "慧为旗下子品牌 LincPlus" and "子公司 LincPlus" (sub-brand / subsidiary) — https://www.techvision.com.cn/News_details/68.html (2025-05-27). LincPlus self-describes as "a publicly listed company headquartered in Shenzhen… 500 employees… $80M sales" — i.e. the same entity — https://www.lincplustech.com/about.html
- Commercial consequence: no third-party ODM customer to lean on for source drops; support requests go to the same company that wrote the BSP. `techvision.s0mp1rc` in your build string is therefore the **parent company's** branch tag.

**Platform siblings for `tb8781p1_64_wifi` / MT8781**
| Device | Evidence | ROM-community value |
|---|---|---|
| Techvision's own **"MT8791/MT8781 11 inch 2K tablet"** (white-label) | https://en.wulu.com/supplier/details/403a423427fb4780a79d6da1a0a82a10 | The reference design; rebadged by several small brands. **[UNVERIFIED]** which brands. |
| **Acer ACTAB1225E / ATAB1225E** — 11.97″ 2000×1200, Android 14, 6/128, Wi-Fi 5 + BT 5.2, 10 000 mAh, 90 Hz | https://www.gigantti.fi/product/puhelimet-tabletit-ja-alykellut/tabletit/acer-actab1225e-6128-gb-1197-tabletti/853157 ; chipset listed as **MT8781V/NA** at https://batterymentor.com/devices/acer-greatwall-atab1225e | A14 + same SoC; **[UNVERIFIED]** that its board string is `tb8781p1_64_wifi` (batterymentor lists SoC only). Worth probing: if it matches, it is the single most valuable firmware donor (A14 vendor blobs). |
| **Primebook 2 / 2 Pro / 2 Max** (India, Android-laptop, 11.6–15.6″) — Helio G99/MT8781, Android 15 | https://ondc.bajajfinservmarkets.in/electronics/product/primebook-2-pro-14-mediatek-helio-g99-mt8781-octa-core/6a0f9ffe4e9b065783f6085a | A Geekbench ML entry for a "Primebook" reports board **`tb8781p1_64_wifi`** — https://browser.geekbench.com/ml/v0/inference/433048 . Strong same-board-string match; the page renders fields blank in extraction, so treat as **probable but unconfirmed**. Android 15 on the same board implies a much newer BSP exists somewhere. |
| **Alldocube iPlay 50 Pro / 50 mini Pro / 60 mini Pro** — Helio G99, 10.4″ 2000×1200, 8/128 UFS 2.2 (466 g) | https://benchmarks.ul.com/hardware/tablet/Alldocube+iPlay+50+Pro+review | **Best ROM community of any G99 tablet**: unlock guides, GSI flashing, LineageOS 21 and crDroid reports — https://xdaforums.com/t/alldocube-iplay-50-mini-spreadtrum-t606-unlock-bootloader.4624503/ , https://xdaforums.com/t/which-gsi-lineageos-to-choose-iplay-60-mini-pro.4752490/ . An XDA user already cross-flashed **iPlay 50 Pro firmware onto a T3** with SP Flash Tool (it flashed cleanly but did not revive the dead unit) — https://xdaforums.com/t/firmware-tablet-lincplus-t3.4736040/ |
| Generic ODM "G-tab MEGA12" etc. — Helio G99 MT8781, 12″ 2K, Android 15 | https://www.banggood.com/ru/G-tab-MEGA12-Helio-G99-MT8781-Octa-Core-8GB+8GB-Virtual-Memory-256GB-ROM-Netflix-Widevine-L1-4G-LTE-12-Inch-2K-Screen-Android-15-Tablet-PC-p-2034586.html | Shows Android 15 BSPs exist on MT8781; low documentation value. |

**"Tecksir"**: no evidence of any such tablet brand on MT8781 — repeated searches return nothing relevant. **[UNVERIFIED / likely non-existent]**; possibly a garbled recollection of "Teclast" or "TECLAST T60"-class devices (that one is Allwinner, not MTK) — https://xdaforums.com/t/teclast-t60-a-12-tablet-130-with-impressive-specs.4665930/

---

## 4. Community activity (root / GSI / unlock)

**XDA — the only real thread, and it is a firmware-recovery thread, not a dev thread**
- https://xdaforums.com/t/firmware-tablet-lincplus-t3.4736040/ (opened 2025-05-11, active through 2026-07-21). Contents:
  - OP bricked a T3, flashed **Alldocube iPlay 50 Pro** firmware via SP Flash Tool; flash succeeded, device stayed dead.
  - 2026-01-28: another member reports "**I managed to find the official ROM… The support team from LincPlus provided me with the ROM.**"
  - 2026-07-21: that member posts the Drive `.rar` (§2) and states: "**If you want to install a new operating system like Crdroid, you can—I've even done it myself.**" He attributes bricking to not transferring "the system key file" during a Windows-side flash. **[UNVERIFIED]** — no build name, no log, no screenshots; treat "crDroid GSI booted on T3" as an unconfirmed user claim, but it is the only direct evidence that the bootloader/vbmeta can be bypassed on this device.
- A separate post reports a T3 owner asking whether **mtkclient** works on Helio G99/MT8781 (surfaced via XDA search snippet; the thread is the MTKClient guide) — implies preloader/DA-level access was the community's first instinct.
- **No** XDA device forum, no TWRP, no device tree, no LineageOS/crDroid official or unofficial thread for LincPlus T3.

**Reddit** — owner discussion only, no development:
- https://www.reddit.com/r/androidtablets/comments/18nwcoz/lincplus_t3_is_incredible_for/ (launch impressions, Widevine L1, 4 speakers, no headphone jack; later comments note the 6 GB re-spin and that "it probably won't get android updates")
- https://www.reddit.com/r/androidtablets/comments/1def2l4/been_looking_for_lincplus_t3_for_months_now_but/ (discontinued by mid-2024; T4 at double the price)
- Screen-failure thread: https://www.reddit.com/r/androidtablets/comments/1fae68i/lincplus_t3_screen_has_gone_faulty_after_a_couple/

**4PDA** — no LincPlus T3 thread exists. LincPlus appears only incidentally in the general Android-tablet comparison thread (an owner noting the same touch-digitizer bug on **LincPlus M8** and **Alldocube iPlay 70 mini Pro**) — https://4pda.to/forum/index.php?showtopic=... (general thread; found via site search, no dedicated topic).

**GitHub** — nothing for the tablet. All "LincPlus" repos are about the **LincStation NAS** line (e.g. https://github.com/bourbonicfisky/lincstation-e1-debian). No kernel, no device tree, no `tb8781p1` repo.

**Telegram** — no LincPlus channel found. The only MT8781-adjacent channels are generic patched-recovery/ROM dumps (e.g. `t.me/physwizz2` posts MT8781 Helio G99 patched recoveries) — not device-specific.

**Net assessment:** essentially zero dev community. Everything must be bootstrapped from the MT8781/Helio G99 generic knowledge base (mtkclient, SP Flash Tool, AVB/vbmeta disable, arm64 GSI) rather than from device-specific work.

---

## 5. Official support, update history, GPL status

- **Tablet line is end-of-life and scrubbed.** lincplustech.com now sells only LincStation NAS + LincStudio S1; the store's product filter shows exactly **one** tablet, "LincStudio S1", **sold out** — https://store.lincplustech.com/collections/all . The downloads page carries **zero** tablet firmware or tablet manuals, only NAS/LincOS content — https://www.lincplustech.com/download.html
- **Official update history:** shipping A13 with 2023-04 patch → one known build dated 2024-10-16 with 2024-09-05 patch. No A14. No published changelog, no OTA archive. **[UNVERIFIED]** whether further OTAs exist beyond 2024-10.
- **Support channel that actually works:** `support@lincplustech.com` — https://store.lincplustech.com/pages/contact-us . Empirically the only route to stock firmware (XDA, §4). Expect a manual, human-fulfilled ROM request rather than a download page.
- **GPL / kernel source: NOT PUBLISHED.** No kernel source, tarball, or "open source" page exists on lincplustech.com or techvision.com.cn; no LincPlus/Techvision kernel repo on GitHub; no GPL request thread answered. Searching "Lincplus kernel source", "Lincplus GPL", "LincPlus open source", "慧为 开源" returns nothing device-related. This is a plain GPLv2 §3 violation for the shipping kernel (5.10.209-android12). The realistic lever is a written request to support@lincplustech.com citing GPLv2 §3 and the exact build string `TVE1070M_US_MT8781_A13_WIFI_user_20241016`; precedent (the ROM release) suggests they do respond to direct requests, but there is no evidence anyone has received source. **[UNVERIFIED]** whether they would comply.

---

## 6. Implications for the GSI project (short)

1. Vendor API 31 + A13 system + 5.10 GKI-era kernel ⇒ a **system-only GSI (Treble) swap** is the only realistic path; full A14/A15 vendor upgrades would need A14+ vendor blobs from a sibling (Acer ACTAB1225E is the candidate to probe).
2. Helio G99/MT6789-generation devices are reported **arm64, A/B, dynamic partitions, seamless updates** — https://community.e.foundation/t/e-os-android-14-2-7-gsi-bring-up/64761/13 . **[UNVERIFIED for T3 specifically]** — confirm with `adb shell getprop ro.build.ab_update`, `ro.boot.slot_suffix`, `ro.treble.enabled`, and `fastboot getvar all`.
3. Entry vector that has actually been demonstrated on this hardware is **MTK BROM/preloader via mtkclient or SP Flash Tool** (XDA OP flashed a foreign MT8781 image), not `fastboot flashing unlock` — no T3 unlock token/`oem unlock` evidence exists anywhere.
4. Preserve the stock ROM: the only public copy is the XDA Drive `.rar` (`Copia de T3-US.rar`). Pull your own full dump (all partitions incl. `nvram`/`nvdata`/`persist`/`md1img`) before touching anything — NVRAM loss on MTK kills Wi-Fi/BT MAC and IMEI-less Wi-Fi-only units still need `persist` for calibration.
