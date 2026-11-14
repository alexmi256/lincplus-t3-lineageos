# Build pipeline

Run from the repository root. Each step is idempotent and can be re-run.

```
00-extract-oem.sh   pull vendor/product/system_b out of YOUR stock super.img   (needed once)
01-build-toolchain  build the ubuntu:24.04 builder image                       (~5 min)
02-sync-source      repo init + repo sync lineage-22.2                          (~180 GB, long)
03-build            apply the GSI patch set and make systemimage                (~2 h)
04-sign             optional: target-files + otatools + release-keys signing    (~30 min)
05-package-super    Widevine identity patch + assemble super.img                (~5 min)
06-flash            flash super, wipe data, reboot                              (~5 min)
```

Set anything you like in the environment first — see `env.sh`:

```bash
export WORKDIR=$HOME/los22
export TARGET=64GN          # GApps; 64VN for vanilla
scripts/01-build-toolchain.sh
scripts/02-sync-source.sh
```

## Why the pipeline looks like this

- **Step 0 exists** because the OEM `vendor` partition is not ours to redistribute. Every user
  extracts it from their own firmware. Nothing in this repo contains vendor code.
- **Step 4 is optional.** Unsigned builds work and boot; they simply carry the AOSP testkey. Signing
  is what makes the image shareable and is what `ro.build.tags=release-keys` requires.
- **Step 5 is mandatory for Widevine L1.** Skipping it boots fine and drops you to L3.

## Requirements

- x86_64 Linux with Docker
- **≥64 GB RAM** and **≥400 GB free SSD** for the tree plus `out/`
- Android platform-tools (`adb`, `fastboot`) on the host for step 6
- The OEM firmware package for your unit, as a rollback path

## Notes and gotchas

- **Do not pass `-u $(id -u):$(id -g)` to docker run.** On a rootless daemon the bind mounts become
  unwritable (`cannot make .repo directory: Permission denied`). `env.sh` deliberately omits it.
- **Never use `set -u` around `source build/envsetup.sh`** — it kills `lunch` silently.
- `make_key` outputs `.pk8`, but APEX signing needs a PEM private key: `convert-pem.sh` does that.
- `lpmake` / `lpunpack` / `lpdump` come from AOSP `otatools`, not from a distro package. After
  step 4 they exist in `$SRC/out/host/linux-x86/bin`.
- Warm `ccache` makes rebuilds roughly 3-5× faster than the first run.
