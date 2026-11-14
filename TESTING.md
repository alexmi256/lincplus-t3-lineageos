# Test checklist

Run this on your T3 after flashing. Copy the result table at the bottom into a GitHub issue.

Most items are one command or one tap. Where a command is given, paste the **output**, not just "ok".

---

## 0. Basics

```bash
adb devices                                   # expect: SERIAL  device
adb shell getprop ro.build.version.release    # expect: 15
adb shell getprop ro.build.tags               # expect: release-keys
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.product.brand            # expect: Lincplus (patched images)
adb shell getprop ro.boot.verifiedbootstate   # expect: orange
adb shell settings get secure user_setup_complete   # 1 once setup finished
```

- [ ] Boots without a bootloop (leave it 10 minutes, check it did not reboot)
- [ ] Setup wizard completes
- [ ] Screen rotation works
- [ ] Lock screen + PIN unlock work
- [ ] Reboot → still boots (do it twice; bootloop bugs often show on the second boot)

## 1. Wi-Fi

```bash
adb shell dumpsys wifi | grep -m3 -E "Wi-Fi is|mNetworkInfo|SSID"
adb shell ip addr show wlan0
adb shell getprop dhcp.wlan0.ipaddress
```

- [ ] Connects to a WPA2 network
- [ ] Survives sleep/wake
- [ ] MAC address matches the stock ROM (`adb shell ip link show wlan0`)
- [ ] Hotspot / tethering can be enabled

## 2. Bluetooth

```bash
adb shell dumpsys bluetooth_manager | head -20
```

- [ ] Turns on, scans, pairs with headphones or a phone
- [ ] A2DP audio plays through the headset
- [ ] MAC address matches stock
- [ ] BLE device visible (any smart device / beacon app)

## 3. Audio

- [ ] Speaker playback (music/video)
- [ ] Headphone jack (if the unit has one) and USB-C audio
- [ ] Microphone records (voice recorder app)
- [ ] Volume keys adjust the right stream
- [ ] No crackle/pops at low volume

## 4. Camera

```bash
adb shell dumpsys media.camera | head -20     # lists detected cameras
```

- [ ] Rear camera preview + still capture
- [ ] Front camera preview + still capture
- [ ] Video recording (rear and front)
- [ ] Flash / torch toggle if present

## 5. Sensors

```bash
adb shell dumpsys sensorservice | head -30
```

- [ ] Auto-rotate responds to tilting
- [ ] Accelerometer values change smoothly (sensor test app)
- [ ] Gyroscope present and reporting
- [ ] Light sensor changes screen brightness
- [ ] Proximity sensor if fitted

## 6. Video, DRM and Widevine

```bash
adb shell dumpsys media.player | head -20
```

- [ ] YouTube plays at 1080p without stutter
- [ ] A DRM-protected stream plays (Netflix / Disney+ / Prime) — this is the L1 test that matters
- [ ] DRM Info app reports **Security Level L1**, HDCP 2.3, 50 sessions
- [ ] HD playback actually starts in the streaming app (L1 alone does not guarantee app approval)

## 7. Storage and USB

```bash
adb shell df -h /data
adb shell sm list-volumes all
```

- [ ] Internal storage shows the expected ~128 GB
- [ ] SD card mounts if the unit supports one
- [ ] MTP file transfer works from a PC
- [ ] USB OTG device (mouse/keyboard/stick) works

## 8. Encryption and lockscreen

```bash
adb shell getprop ro.crypto.state      # expect: encrypted
adb shell getprop ro.crypto.type       # expect: file
```

- [ ] PIN/password unlock works after a full reboot
- [ ] Changing the PIN works
- [ ] No "decryption unsuccessful" on boot

## 9. Google Play

- [ ] Sign in to Play Store
- [ ] Play Store shows the device as **Play Protect certified** (Settings → About → Play Protect certification)
  - If it says *not certified*: register the GSF ID at <https://www.google.com/android/uncertified>
- [ ] Install an app successfully
- [ ] Play Services updates itself without crashing

## 10. Power and sleep

- [ ] Screen-off battery drain overnight (< ~3 %/h at idle)
- [ ] Charging works and reports correctly
- [ ] No abnormal heat at idle
- [ ] Deep sleep reached (`adb shell dumpsys deviceidle | head -20`)

## 11. Regression checks specific to this build

- [ ] Second reboot does not bootloop
- [ ] Flashing the same `super` again + wipe still boots (repeatability)
- [ ] Switching between the A14 and A15 images works with a wipe

---

## Results template

Copy this into the issue and fill it in:

```
Device:            LincPlus T3 (T3_US), 8/128
Image:             super-lin22-signed.img  (or A14 equivalent)
SHA-256 verified:  yes / no
Android / SPL:     15 / 2026-11-01
Bootloader:        unlocked (orange) / locked
Widevine:          L1 / L3 / unknown   (SysID:      )

Boot:              pass / fail  (notes)
Wi-Fi:             pass / fail  (MAC matches stock: yes/no)
Bluetooth:         pass / fail  (A2DP: yes/no)
Audio speaker:     pass / fail
Audio mic:         pass / fail
Camera rear:       pass / fail
Camera front:      pass / fail
Video recording:   pass / fail
Auto-rotate:       pass / fail
Gyro / light:      pass / fail / absent
Video decode:      pass / fail  (1080p H.264 / HEVC / VP9)
DRM playback:      pass / fail  (app name:        )
MTP:               pass / fail
Encryption:        pass / fail
Play certified:    yes / no / not tested
Battery idle:      pass / fail  (% per hour:    )
Reboot stability:  pass / fail  (reboots survived:    )

Anything else:
```
