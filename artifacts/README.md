# Downloadable images

These are **flashable `super.img` files**, not installer zips. Flash with fastboot; see
[`../docs/07-procedure.md`](../docs/07-procedure.md).

## What to download

| Asset | Android | Size (bytes) | SHA-256 |
|---|---|---|---|
| `super-lin22-signed.img` | **15** — LineageOS 22.2, release-keys, Widevine L1 | 9,663,676,416 | `7c14cb486bbff10e96ce873a6cf66dac46a2a78b2dd65fadcf326bbc6f03511e` |
| `super-stockid.img` | **14** — LineageOS 21.0, release-keys, Widevine L1 | 9,663,676,416 | `b801d32f0b4bdd3d6b3961d9974caa9dd5e132ed7090e0cdd0ebc346cd319adb` |
| `vbmeta-flags3.img` | required alongside either image | 8,192 | `f3a8aaf574ef079041b2b9b28919d60294eb49cf20527f54a7208ded1592e5b8` |
| `lineage-22.2-signed.img` | the raw A15 system image inside `super-lin22-signed` | 3,121,930,240 | `075e40a8df753db1aa92101adf2cca21f252e8b09bfbb97d249759625d09601c` |

`vbmeta-flags3.img` is the OEM `vbmeta` re-emitted with `Flags: 3` (verification and
verification-error disabled). Any modified `super` needs it, or the device will not boot.

## GitHub's size limit, and why these are split

GitHub caps a **release asset at 2 GiB**. The `super` images are 9 GiB each, so they must be split
into parts and rejoined after download. `scripts/split-for-release.sh` does the splitting and writes
a checksum manifest.

Download **all parts of one image**, then:

```bash
cat super-lin22-signed.img.part-* > super-lin22-signed.img
sha256sum super-lin22-signed.img
# must equal 7c14cb486bbff10e96ce873a6cf66dac46a2a78b2dd65fadcf326bbc6f03511e
```

Parts are named `super-lin22-signed.img.part-aa`, `.part-ab`, … in order; `cat` sorts them correctly
as long as you use the glob.

## Alternative hosting

2 GiB parts are annoying. If you would rather host single files, archive.org and SourceForge both
accept 9 GB uploads and give stable direct links — put the link in this file and in the README table.
GitHub Releases is convenient for discovery, not for large binaries.

## Compressing first (optional)

`super.img` is largely sparse, so it compresses well. If you compress, publish `.gz` parts and
document the `gunzip` step; keep the SHA-256 of the **uncompressed** image as the verification value
so it stays comparable with what other users produce.

## Publishing a release

```bash
gh release create v1.0.0 \
  --title "LineageOS 22.2 (Android 15) + LineageOS 21.0 (Android 14) for LincPlus T3" \
  --notes "See README.md for what works. Verify SHA-256 after download."

gh release upload v1.0.0 super-lin22-signed.img.part-* super-stockid.img.part-* vbmeta-flags3.img
```

## Verifying before you flash

```bash
sha256sum -c SHA256SUMS.txt      # after downloading every part and rejoining
```

Never flash an image whose hash you have not checked. A truncated `super` flashes fine and then
bootloops.
