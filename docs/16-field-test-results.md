# Field test results

Results reported by the maintainer on real hardware. One unit, one report — treat this as evidence,
not a guarantee, and add yours via the [device report template](../.github/ISSUE_TEMPLATE/device-report.md).

## 2026-11-14 — Android 15 (`super-lin22-signed.img`, release-keys, identity-patched)

Unit: test unit (8/128 GB, `T3_US`), bootloader unlocked, flashed with a full userdata wipe.

| Area | Result | Notes |
|---|---|---|
| Boot / setup wizard | ✅ works | Boots to a working launcher, GApps present |
| Wi-Fi | ✅ works | Connects and stays connected |
| Camera — rear | ✅ works | Preview + stills |
| Camera — front | ✅ works | Preview + stills |
| Audio — speaker | ✅ works | Media playback fine |
| Bluetooth | 🟡 partial | Device list populates; no pairing/audio test performed yet |
| Brightness | 🟡 partial | Slider responds, but the **lower third of the range barely changes brightness**. Enabling the brightness options in GSI settings (Phh Treble Settings) did **not** make it dimmer |
| Widevine | ✅ L1 | SysID 29739, HDCP 2.3, 50 sessions, measured via DRM Info |

### Analysis: the brightness issue

Two plausible causes, both consistent with what was observed:

1. **Backlight curve lives in the vendor HAL.** The GSI drives a generic brightness curve through
   `lights`/display HAL, while stock firmware used a device-tuned table. The bottom of the range maps
   to PWM values that are already near the panel minimum, so further slider movement does nothing.
2. **Minimum brightness floor is set high.** Some MediaTek panels refuse to go below a certain
   backlight value; the GSI writes values the panel clamps.

Either way this is not fixable from the GSI — it needs a device tree or a vendor overlay. Practical
workarounds: a screen-dimming overlay app, Night Light, or a lower `persist.sys` brightness floor if a
future GSI exposes one.

## Not yet tested

Video recording, headphone jack / USB-C audio, microphone, sensors (accelerometer, gyroscope, light,
proximity), auto-rotate, hardware video decode, MTP/USB file transfer, encryption full cycle, battery
idle drain, Play Protect certification.

If you have a unit, run [`TESTING.md`](../TESTING.md) and open an issue — every row that moves is
useful.
