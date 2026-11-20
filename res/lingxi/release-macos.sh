#!/usr/bin/env bash
# Sign, zip and attach the macOS app to the GitHub Release of the current
# version, which the in-app updater (flutter/lib/lingxi/lingxi_update.dart)
# picks up as LingxiDesk-<version>-macos-arm64.zip.
#
# Usage: res/lingxi/release-macos.sh <path/to/LingxiDesk.app> [notes.md]
#
# Build the app first (see docs). The release is created if it does not exist
# yet (then notes.md is required); otherwise the zip is added to it. Run
# release-android.sh first to publish both from one release.
#
# Every release must be signed with the same identity
# (~/dev-tools/lingxi-sign-mac.sh), or the updater refuses it and macOS
# privacy permissions reset.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="${1:?usage: $0 <LingxiDesk.app> [notes.md]}"
NOTES="${2:-}"
REPO=Allen-1002/lingxi-desk
SIGN="${LINGXI_MAC_SIGN:-$HOME/dev-tools/lingxi-sign-mac.sh}"
[[ -d "$APP" ]] || { echo "$APP not found" >&2; exit 1; }
[[ -x "$SIGN" ]] || { echo "signing script $SIGN not found" >&2; exit 1; }

VER=$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' flutter/pubspec.yaml)
TAG="v$VER"
APPVER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$APPVER" == "$VER" ]] || { echo "app version $APPVER != pubspec $VER; rebuild" >&2; exit 1; }

"$SIGN" "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier"

OUTDIR=flutter/build/lingxi-release
mkdir -p "$OUTDIR"
OUT="$OUTDIR/LingxiDesk-$VER-macos-arm64.zip"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$OUT" --clobber --repo "$REPO"
else
  [[ -f "$NOTES" ]] || { echo "release $TAG does not exist; pass notes.md" >&2; exit 1; }
  git fetch -q origin
  [[ -n "$(git branch -r --contains HEAD)" ]] || { echo "HEAD is not pushed" >&2; exit 1; }
  gh release create "$TAG" "$OUT" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "灵犀 $VER" --notes-file "$NOTES"
fi
echo "attached $OUT to $TAG"
