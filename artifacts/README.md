# Downloadable images

These are **flashable `super.img` files**, compressed with xz. Flash with fastboot; see
[`../docs/07-procedure.md`](../docs/07-procedure.md).

## What to download

| Asset | Android | `.xz` size | Image size | SHA-256 of `.xz` | SHA-256 of image |
|---|---|---|---|---|---|
| `super-lin22-signed.img.xz` | **15** — LineageOS 22.2, release-keys, Widevine L1 | 2,058,264,928 B (1.92 GiB) | 9,663,676,416 B | `a7e6766851156cd1fbb74aa2122308fb22522f0c27aed7c7094fde699c1bc8a3` | `7c14cb486bbff10e96ce873a6cf66dac46a2a78b2dd65fadcf326bbc6f03511e` |
| `super-stockid.img.xz` | **14** — LineageOS 21.0, release-keys, Widevine L1 | 2,074,452,936 B (1.93 GiB) | 9,663,676,416 B | `1b6326fe24a9bb99eca140cc0da175d7ff1a1b3286b61035690c545f5e6d077f` | `b801d32f0b4bdd3d6b3961d9974caa9dd5e132ed7090e0cdd0ebc346cd319adb` |
| `vbmeta-flags3.img` | required alongside either image | 8,192 B | 8,192 B | — | `f3a8aaf574ef079041b2b9b28919d60294eb49cf20527f54a7208ded1592e5b8` |

Compression takes each 9.66 GB `super` down to ~2.06 GB — **about 21 % of the original**, because the
image is largely empty space. That also means no part-splitting is needed: both files sit under
GitHub's 2 GiB per-asset ceiling.

## Decompress

```bash
# Linux / macOS (xz is preinstalled on most distros; `apt install xz-utils` otherwise)
xz -d super-lin22-signed.img.xz          # -> super-lin22-signed.img

# Windows: right-click -> 7-Zip -> Extract, or
# 7z x super-lin22-signed.img.xz
```

Then verify **before flashing**:

```bash
sha256sum super-lin22-signed.img
# must be 7c14cb486bbff10e96ce873a6cf66dac46a2a78b2dd65fadcf326bbc6f03511e
```

A truncated image flashes perfectly happily and then bootloops, so this check is the one that saves
you an evening.

`vbmeta-flags3.img` is the OEM `vbmeta` re-emitted with `Flags: 3` (verification and
verification-error disabled). Any modified `super` needs it, or the device will not boot.

## If the upload is rejected

Both files are ~1.92 GiB, i.e. about 96 % of the cap — fine in practice, but close enough that a
future GitHub change could bite. If an upload fails, split and rejoin:

```bash
scripts/split-for-release.sh super-lin22-signed.img 1900M
# users then: cat super-lin22-signed.img.part-* > super-lin22-signed.img
```

## Alternative hosting

There is nothing to post but ~4 GB of files; archive.org or SourceForge accept single 9 GB uploads
and give stable direct links, which is friendlier than parts. GitHub Releases is convenient for
discovery, not ideal for binaries.

## Publishing a release

```bash
gh release create v1.0.0 \
  --title "LineageOS 22.2 (Android 15) + 21.0 (Android 14) for LincPlus T3" \
  --notes "Read README.md for what works. Verify SHA-256 before flashing."

gh release upload v1.0.0 \
  super-lin22-signed.img.xz super-stockid.img.xz vbmeta-flags3.img
```

## Provenance

| Field | A15 | A14 |
|---|---|---|
| LineageOS branch | `lineage-22.2` @ 2026-11-14 | `lineage-21.0` |
| AOSP base | `BP1A.250505.005` | `UQ1A.240205.004` |
| Security patch | 2026-11-01 | 2026-11-01 |
| Signing | our release keys | upstream release keys |
| Identity patch | applied (`Lincplus` / `T3_US`) | applied |
| Widevine | L1, SysID 29739 | L1, SysID 29739 |
