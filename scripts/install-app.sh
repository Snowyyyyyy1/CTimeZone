#!/bin/bash
# Build a Release copy and install it to ~/Applications, replacing any
# previous install. Local builds use the committed public key, so the
# installed copy receives updates like a downloaded one.
set -euo pipefail
cd "$(dirname "$0")/.."
export TUIST_SKIP_UPDATE_CHECK=1

tuist generate --no-open
tuist xcodebuild build -scheme CTimezone -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build

SRC=".build/Build/Products/Release/CTimeZone.app"
DEST="$HOME/Applications/CTimeZone.app"

pkill -x CTimeZone 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
open "$DEST"
echo "Installed $DEST"
