#!/usr/bin/env bash
# Download the rustdesk-server programs (hbbs + hbbr) that the desktop app
# ships for one-click server deploy, and repack them per architecture as
# lingxi-server-linux-<amd64|arm64>.tar.gz in <out dir> (default
# flutter/build/lingxi-server). Servers always have tar, not always unzip.
#
# Usage: res/lingxi/fetch-server-bins.sh [out dir]
set -euo pipefail
VER=1.1.16
cd "$(dirname "$0")/../.."
OUT="${1:-flutter/build/lingxi-server}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for pair in amd64:amd64 arm64:arm64v8; do
  arch="${pair%%:*}"; up="${pair##*:}"
  dst="$OUT/lingxi-server-linux-$arch.tar.gz"
  [[ -s "$dst" ]] && { echo "have $dst"; continue; }
  curl -fsSL -o "$TMP/$arch.zip" \
    "https://github.com/rustdesk/rustdesk-server/releases/download/$VER/rustdesk-server-linux-$up.zip"
  mkdir -p "$TMP/$arch"
  (cd "$TMP/$arch" && unzip -q "../$arch.zip")
  dir="$(dirname "$(find "$TMP/$arch" -type f -name hbbs | head -1)")"
  [[ -x "$dir/hbbs" || -f "$dir/hbbs" ]] || { echo "hbbs not found in $up zip" >&2; exit 1; }
  chmod 755 "$dir/hbbs" "$dir/hbbr"
  # --no-xattrs: macOS tar would otherwise add LIBARCHIVE.xattr headers that GNU tar
  # on the server prints warnings about.
  COPYFILE_DISABLE=1 tar --no-xattrs -czf "$dst" -C "$dir" hbbs hbbr
  echo "made $dst ($(du -h "$dst" | cut -f1))"
done
