#!/usr/bin/env bash
set -e

IMG="$1"
SRC_DIR="/workdir"
TMP_DIR="/data"

if [[ -z "$IMG" ]]; then
  echo "Usage: pishrink <image-file>" >&2
  exit 1
fi

# 1) Copy the host image into the VM’s native volume
mkdir -p "$TMP_DIR"
cp "$SRC_DIR/$IMG" "$TMP_DIR/$IMG"

# 2) Shrink it in-place inside the VM filesystem
pishrink "$TMP_DIR/$IMG"

# 3) Copy the result back to the shared folder
cp "$TMP_DIR/$IMG" "$SRC_DIR/${IMG%.img}-shrunk.img"
