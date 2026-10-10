#!/bin/bash
# Package an .app into a drag-to-install DMG and verify the signature
# survived the round trip.
#
# Usage: scripts/make-dmg.sh <path/to/CTimeZone.app> <output.dmg>
set -euo pipefail

APP="$1"
OUT="$2"
NAME="$(basename "$APP" .app)"

STAGE="$(mktemp -d)"
MOUNT="$(mktemp -d)"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$MOUNT"' EXIT

# ditto keeps symlinks and extended attributes; cp -R can break the
# embedded Sparkle.framework signature.
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null

hdiutil attach "$OUT" -mountpoint "$MOUNT" -nobrowse -quiet
codesign --verify --deep --strict "$MOUNT/$NAME.app"
echo "Created $OUT ($(du -h "$OUT" | cut -f1)), signature verified after mount"
