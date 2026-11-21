#!/usr/bin/env bash
# Build the signed Android APK and publish it as a GitHub Release, which the
# in-app updater (flutter/lib/lingxi/lingxi_update.dart) picks up.
#
# Usage: res/lingxi/release-android.sh <notes.md>
#
# Before each release, bump `version:` in flutter/pubspec.yaml (both the name
# and the +build number, e.g. 0.3.1+81), commit and push.
#
# Needs, on the build machine only (never in the repo):
#   ~/.config/lingxi-desk/android-release.properties with
#     storeFile=/absolute/path/android-release.jks
#     storePassword=...  keyAlias=...  keyPassword=...
#   Every release must use this same key, or phones cannot update in place.
#   ~/dev-tools/lingxi-android-env.sh and a logged-in `gh`.
# The Rust library must already be in flutter/android/app/src/main/jniLibs
# (set BUILD_RUST=1 to rebuild it with flutter/ndk_arm64.sh first).
set -euo pipefail
cd "$(dirname "$0")/../.."

NOTES="${1:?usage: $0 <notes.md>}"
[[ -f "$NOTES" ]] || { echo "notes file $NOTES not found" >&2; exit 1; }
REPO=Allen-1002/nimbo
PROPS="${LINGXI_SIGNING:-$HOME/.config/lingxi-desk/android-release.properties}"
[[ -f "$PROPS" ]] || { echo "missing signing config $PROPS" >&2; exit 1; }

VER=$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' flutter/pubspec.yaml)
[[ -n "$VER" ]] || { echo "cannot read version from flutter/pubspec.yaml" >&2; exit 1; }
TAG="v$VER"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "release $TAG already exists; bump version in flutter/pubspec.yaml" >&2
  exit 1
fi
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "working tree has changes; commit first" >&2; exit 1; }
git fetch -q origin
[[ -n "$(git branch -r --contains HEAD)" ]] || { echo "HEAD is not pushed" >&2; exit 1; }

# shellcheck disable=SC1090
source ~/dev-tools/lingxi-android-env.sh
if [[ "${BUILD_RUST:-0}" == 1 ]]; then
  ./flutter/ndk_arm64.sh
  mkdir -p flutter/android/app/src/main/jniLibs/arm64-v8a
  cp target/aarch64-linux-android/release/liblibrustdesk.so \
    flutter/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so
fi
[[ -f flutter/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so ]] || { echo "librustdesk.so missing; run with BUILD_RUST=1" >&2; exit 1; }

cp "$PROPS" flutter/android/key.properties
trap 'rm -f flutter/android/key.properties' EXIT
(cd flutter && flutter build apk --release --target-platform android-arm64 --split-per-abi)

OUTDIR=flutter/build/lingxi-release
OUT="$OUTDIR/LingxiDesk-$VER-android-arm64.apk"
mkdir -p "$OUTDIR"
cp flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$OUT"
APKSIGNER=$(ls "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "$APKSIGNER" ]]; then "$APKSIGNER" verify --print-certs "$OUT" | grep -i "sha-256"; fi

gh release create "$TAG" "$OUT" --repo "$REPO" --target "$(git rev-parse HEAD)" \
  --title "Nimbo $VER" --notes-file "$NOTES"
echo "published $TAG: $OUT"
