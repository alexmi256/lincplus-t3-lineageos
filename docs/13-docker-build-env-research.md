# Docker build environment for LineageOS 22.2 — research note

Question: can the 22.2 GSI build run inside a container, so nothing gets installed on `build-host`?
Researched 2026-11-13.

## Headline: there is no official LineageOS build image

Docker Hub's `lineageos` namespace returns **zero repositories**. LineageOS' own infrastructure is
Buildkite + bare-metal builders; they do not publish a user-facing build container. Anything you find
is community work.

## What actually exists

| Image | Base | Pulls | Last update | Verdict |
|---|---|---|---|---|
| **`lineageos4microg/docker-lineage-cicd`** | Ubuntu **24.04** (sha-pinned) | 156,681 | **2026-11-13** | the only living option |
| `salvian/docker-lineageos` | Ubuntu 16.04 | 184 | 2018-05-19 | dead |
| `anthodingo/docker-lineageos` | Ubuntu 16.04 | — | 2016-era | dead |
| `jfloff/docker-lineageos` | — | — | unmaintained | dead |

### `lineageos4microg/docker-lineage-cicd` — the de-facto standard

- 556 stars, pushed the day this was written; `latest` tag rebuilt 2026-10-31; ~500 MB.
- Base `ubuntu:24.04` pinned by digest. Directory layout is container-native:
  `SRC_DIR=/srv/src`, `CCACHE_DIR=/srv/ccache`, `ZIP_DIR=/srv/zips`, `LMANIFEST_DIR=/srv/local_manifests`,
  `KEYS_DIR=/srv/keys`, `USE_CCACHE=1`, `CCACHE_SIZE=50G`.
- Package set covers the LineageOS wiki list almost exactly: `bc bison build-essential ccache curl
  flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick kmod lib32ncurses5-dev
  lib32readline-dev lib32z1-dev libdw-dev libelf-dev libgnutls28-dev libsdl1.2-dev libssl-dev
  libxml2 libxml2-utils lz4 pngcrush protobuf-compiler python3-protobuf rsync schedtool
  squashfs-tools xsltproc zip zlib1g-dev`.
- **But it is opinionated.** `ENTRYPOINT /root/init.sh` drives *LineageOS-for-microG device builds*
  — `brunch <device>` for entries in `DEVICE_LIST`, with microG signature spoofing patches applied.
  It bundles **openjdk-8-jdk** (a legacy-branch smell), and `erofs-utils` is not in the package list.

Consequence: it is a good **toolchain environment**, not a GSI builder. Using it means overriding the
entrypoint (`--entrypoint bash`), reusing its deps, and accepting microG-era defaults — or rebuilding
our own image from the same base.

## Recommendation: build a thin image instead

The dependency list is published by LineageOS themselves (`wiki.lineageos.org` build page). Pinning
`ubuntu:24.04` + that exact list + `repo` + ccache is ~20 lines and fully controlled:

```dockerfile
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs \
      gnupg gperf imagemagick kmod lz4 lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
      libgnutls28-dev libsdl1.2-dev libssl-dev libxml2-utils lzop pngcrush protobuf-compiler \
      python3-protobuf rsync schedtool squashfs-tools xsltproc xxd zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo \
    && chmod +x /usr/local/bin/repo
ENV USE_CCACHE=1 CCACHE_DIR=/srv/ccache CCACHE_EXEC=/usr/bin/ccache
WORKDIR /srv/src
```

Why this over the L4M image: the package list comes from the authoritative source rather than a
microG fork's assumptions, there is no entrypoint fighting us, no JDK 8, and rebuilding on a new
LineageOS branch is a one-line base-image bump.

Fallback: if a build step fails on a missing library, add it to this Dockerfile rather than installing
on the host — that keeps the reproducibility promise intact.

## Container design for this build

| Concern | Decision |
|---|---|
| Docker access | Docker 29.9.3 is installed and active on `build-host`, but `user` is **not in the `docker` group** → run as `sudo docker` (no host changes needed) |
| Source tree | bind-mount `~/lineage` → `/srv/src`; **owned by the host user** |
| UID mapping | run with `--user $(id -u):$(id -g)` and `HOME` set, otherwise `repo sync` writes root-owned files and every later host-side operation needs sudo |
| ccache | host dir `~/ccache` → `/srv/ccache`, `-M 100G`; survives image rebuilds |
| Output | host dir `~/out` → `/srv/out`, so artefacts land outside the container |
| Privileges | start unprivileged; AOSP's `mkuserimg`/`e2fsdroid` do not need loop mounts. Add `--cap-add SYS_ADMIN` **only** if a specific step demands it |
| Overhead | negligible vs 62 GiB RAM; the build is RAM- and I/O-bound, not container-bound |
| Persistence | the container is disposable — only the three bind mounts matter |

## Caveats worth knowing before committing

1. **Disk is the constraint, not the container.** 606 GB free on `/`; one tree (~100 GB) + `out/`
   (~60–100 GB) + 100 GB ccache fits, two trees does not. Keep ccache at 100 G, not 200 G.
2. **`repo` requires a git identity** inside the container (`user.name`, `user.email`) or the first
   commit-creating step fails with a confusing error.
3. **`--git-lfs`** is required on `repo init` for `lineage-22.2`; `git-lfs` must be in the image
   (it is, above).
4. **Time zones/locale**: set `TZ=UTC` to keep build artefact timestamps deterministic.
5. **Docker-in-Docker is not needed.** Everything runs in one container; no nested daemon.

## Open questions

1. Whether `sudo docker` is acceptable long-term, or whether to add `user` to the `docker` group
   (a host change — deferred, since nothing is to be installed yet).
2. Whether to keep the L4M image around as a comparison toolchain, purely as a fallback if our thin
   image hits a missing dependency.
3. Whether the build needs `--cap-add SYS_ADMIN` for the `super`/sparse-image stages. Test with a
   short target (e.g. a `treble 64VN` build attempt that fails fast) before a full run.

## Addendum — plain AOSP images (surveyed after the LineageOS pass)

There is **no official Google/AOSP build image** either; Google's CI images aren't public. The
community landscape, by actual usage:

| Image | Base | Pulls / stars | Last update | Gaps for Lineage 22.2 |
|---|---|---|---|---|
| **`accupara/aosp`** (Crave.io) | Debian 13 | **92.7k pulls** | **2026-10-07** | no `git-lfs`, no 32-bit multilib, no `erofs-utils`; JDK 11 |
| `alexanderwolz/aosp-docker` | — | 21★ | 2025-01 | advertises "AOSP14+", compose-based, good docs |
| `EndCredits/Docker_Build_AOSP` | Debian 12 | 14★ | **2025-11** | most complete deps, but China-mirrored `repo`, `TZ=Asia/Shanghai`, `libncurses5` is not in bookworm |
| `kylemanna/docker-aosp` | Ubuntu | 525★ | **2017** | dead |
| `apon77/aosp-builder` | Ubuntu 20.04 | 39★ | 2021 | stale |
| `openstf/aosp` | — | 3.5k pulls | 2015-era | dead |

Notes that matter:

- **`accupara/aosp` is the most used and most recently rebuilt**, but it is a *base* image: it builds
  `android-tools` 35.0.1 from source and ships `ccache`, `repo`, `clang`, JDK 11 — and not much else.
  It would need `git-lfs`, `lib32z1`/`lib32ncurses`-style multilib packages and `erofs-utils` added
  before a `--git-lfs` Lineage 22.2 sync works.
- **`EndCredits/Docker_Build_AOSP` is the closest to turnkey** — it already installs `git-lfs`,
  `erofs-utils`, `elfutils`, `dwarves`, `patchelf` and takes `userid`/`groupid`/`username` build args,
  which solves the UID-mapping problem for free. Its weaknesses are small-project risk and a
  China-centric mirror/TZ setup that should be changed for a EU host.
- **`alexanderwolz/aosp-docker`** is the best *documented* option (compose file, config dir, explicit
  "AOSP14+" claim), just older.

Verdict unchanged: none of these is LineageOS-aware, so all need at least `git-lfs` and
`erofs-utils`. Given that, a thin self-owned Dockerfile (§Recommendation) is still the least
surprising choice — but `EndCredits` is the best starting point if the preference is to inherit
someone else's tested package set rather than write one.

## Addendum 2 — what the in-tree prebuilts actually provide (verified)

The claim that modern AOSP ships its own toolchain is **correct**, and it is the reason the host
image can stay small. Verified against the trees themselves, not documentation summaries:

**AOSP `android15-release` manifest** declares:

```xml
<project path="prebuilts/build-tools"        name="platform/prebuilts/build-tools" />
<project path="prebuilts/clang/host/linux-x86" name="platform/prebuilts/clang/host/linux-x86" />
<project path="prebuilts/jdk/jdk17"          name="platform/prebuilts/jdk/jdk17" />
<project path="prebuilts/jdk/jdk21"          name="platform/prebuilts/jdk/jdk21" />
```

**LineageOS `lineage-22.2` manifest** declares the same set (plus `jdk8` for legacy targets):

```
prebuilts/build-tools, prebuilts/clang/host/linux-x86, prebuilts/jdk/jdk21, prebuilts/jdk/jdk8
```

**`prebuilts/build-tools/linux-x86/bin/`** holds 37 executables, including `ninja`, `make`,
`soong_zip`, `zip2zip`, `ckati`, `bison`, `flex`, `brotli`, `aidl`, `aconfig`. Clang ships as
versioned directories (`clang-r498229b`, …) under `prebuilts/clang/host/linux-x86/`.

Google's own setup page (updated 2026-11-04) states it plainly:

> "The latest release branch of Android comes with prebuilt versions of **OpenJDK, Make, and
> Python 3**, so additional installation steps aren't required."

Consequence for the container: **do not install a JDK, clang, ninja or make.** The host needs glibc,
`git`, `python3` (only because `repo` itself is a Python launcher) and the small package list below.
That is why a ~1 GB image is sufficient for a build that produces tens of gigabytes of output.

### The two claims to discard

1. **"Google maintains a reference Dockerfile whose package list matches the Android 15 release."**
   The file exists at `build/make/tools/docker/Dockerfile` in `android14-release`, `android15-release`,
   `android16-release` and `main` — HTTP 200 on all four — but its contents are:

   ```dockerfile
   FROM ubuntu:14.04
   ... openjdk-7-jdk python ... lib32ncurses5-dev ...
   RUN curl ... prebuilts/jdk/jdk8/+archive/master.tar.gz
   ```

   It is a 2015 relic that survived the branch split because nobody deleted it. It does **not** track
   the release. Building Android 15 with it would fail on the first `apt-get update`.

2. **"`cdlee/aosp-builder` is a maintained Ubuntu 24.04 image tested against Android 15."**
   The image is real but: **851 pulls, 0 stars, no description, not automated**, registered 2025-09-02,
   last pushed 2025-12-16, and no source repository surfaced for it. For an artefact that will run a
   full AOSP build with network access, "one anonymous author, no source, no stars" is exactly the
   supply-chain profile to avoid.

3. Minor: the quoted package list includes `libncurses5`, which **does not exist in Ubuntu 24.04**
   (noble ships `libncurses6`/`libtinfo6`). Including it fails the whole `apt` transaction.

### Minimal, verified Dockerfile

Union of Google's official list and LineageOS' additions, with each extra justified:

```dockerfile
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=UTC

# Google's official host package list for AOSP 9+ (source.android.com, 2026-11-04)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 \
      x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils \
      xsltproc unzip fontconfig python3 repo \
      # LineageOS additions: LFS for `repo init --git-lfs`, cache, erofs images
      git-lfs ccache erofs-utils lz4 rsync bc \
    && rm -rf /var/lib/apt/lists/*

ENV USE_CCACHE=1 CCACHE_DIR=/srv/ccache CCACHE_EXEC=/usr/bin/ccache
WORKDIR /srv/src
```

No `openjdk`, no `clang`, no `ninja`, no `gcc-multilib` — all supplied by the synced tree. Add
`gcc-multilib g++-multilib` back only if a specific legacy target complains.

### What this changes in the plan

Nothing structural — it shrinks Phase 0. The container becomes ~1 GB, the build is unchanged, and the
"net install" on the host stays at zero: Docker pulls the base, the tree supplies the toolchain.

## Addendum 3 — the environment as actually built (2026-11-14)

Built on `build-host` and validated end to end. Facts that differ from the plan above:

**Image:** `los22-builder:latest`, **1.06 GB**, `FROM ubuntu:24.04`. Contains `repo` launcher 2.71,
`git-lfs` 3.4.1, `ccache` 4.9.1, `mkfs.erofs`, `lz4`, `xsltproc`, Python 3.12.3. No JDK, no clang —
as intended, those arrive with `repo sync`.

**Host layout** (`/home/user/build/`):

```
src/     the LineageOS tree (bind -> /srv/src)
ccache/  ccache, limit set to 100 GB (bind -> /srv/ccache)
home/    container HOME, also where build-output/ lands (bind -> /srv/home)
logs/    build logs
out/     created but unused — $OUT stays inside the tree
```

### Rootless Docker breaks the UID-mapping advice in this document

The host runs **rootless Docker** (`docker info` → `Context: rootless`, storage driver `overlayfs`).
Under rootless, the container's **root (uid 0) maps to the host user**, while container **uid 1000
maps to a subuid** (e.g. `100000+1000`). Consequence, measured:

- `docker run -u 1000:1000` → the bind-mounted tree appears owned by `root:root` inside the container
  and **every write fails**: `cannot make .repo directory: Permission denied`,
  `failed to write to /srv/ccache/ccache.conf`.
- Running with the **default user (root inside the container)** → writes succeed, and files land on
  the host owned by `user` (verified: `ccache.conf` created as `1000:1000`).

So the `--user $(id -u):$(id -g)` recommendation earlier in this document is **wrong for a rootless
daemon** and is only correct for rootful Docker. On this host: omit `-u` entirely.

### Other measured details

- Docker group membership works without `sudo` after `usermod -aG docker` plus a fresh SSH session.
- `repo sync -c -j12 --no-tags --force-sync` of `lineage-22.2` pulls **~180 GB** and takes well under
  an hour on this network — considerably larger than the 100 GB estimate, so the 606 GB free disk is
  the binding constraint once `out/` and ccache are added.
- `build_unified.sh` flow: copies `local_manifests_treble/*.xml` into `.repo/local_manifests` →
  `repo sync` → `repopick` three Gerrit changes → applies `patches_platform` then `patches_treble` →
  `lunch lineage_gsi_arm64_gN-<aosp_target_release>-userdebug` → `make installclean` →
  `make systemimage`. Output: `~/build/home/build-output/lineage-22.2-<date>-UNOFFICIAL-gsi_arm64_gN.img`.
- Signing is skipped when `$HOME/.android-certs` is absent (it prompts, then continues with
  `SIGNABLE=false`). That is the wanted behaviour here: AVB is disabled at flash time anyway.



