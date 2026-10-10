#!/bin/bash
# Build CTimeZone and (re)launch the app. Restarts an existing instance.
# Does not touch Claude.app, its config, or any CLI symlink.
set -euo pipefail

cd "$(dirname "$0")"

export TUIST_SKIP_UPDATE_CHECK=1

echo "==> Generating project"
tuist generate --no-open

echo "==> Building (Debug)"
tuist xcodebuild build \
  -scheme CTimezone \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build

APP=".build/Build/Products/Debug/CTimeZone.app"

echo "==> Relaunching $APP"
if pgrep -x CTimeZone >/dev/null 2>&1; then
  pkill -x CTimeZone >/dev/null 2>&1 || true
  sleep 1
fi
open "$APP"
