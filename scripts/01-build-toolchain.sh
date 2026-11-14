#!/bin/bash
# Step 1 - build the container image that supplies the host toolchain.
set -eu
cd "$(dirname "$0")/.."

IMAGE="${BUILDER_IMAGE:-los22-builder}"
docker build -t "$IMAGE" -f scripts/Dockerfile scripts/

echo "--- verifying the toolchain inside the image"
docker run --rm "$IMAGE" bash -c '
  repo --version 2>&1 | tail -1
  git lfs version
  ccache --version | head -1
  python3 -V
  echo "debugfs: $(command -v debugfs || echo MISSING)"
'
echo "OK - image $IMAGE ready"
