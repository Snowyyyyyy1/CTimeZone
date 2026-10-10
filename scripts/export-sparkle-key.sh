#!/bin/bash
# Maintainer only: copy the Sparkle private key from the login keychain into
# the release workflow's secret. The key never touches the terminal or disk
# outside a 0600 temp file that is removed right after.
#
# Losing this key strands every installed copy (they only trust the matching
# public key in Project.swift). Never commit it or paste it anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${1:?usage: scripts/export-sparkle-key.sh <owner/repo>}"
BIN="$(find .build/SourcePackages/artifacts -name generate_keys -type f 2>/dev/null | head -1 || true)"
[ -n "$BIN" ] || { echo "Build once so SwiftPM fetches Sparkle, then retry."; exit 1; }

umask 077
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
"$BIN" --account ctimezone -x "$TMP" >/dev/null
gh secret set SPARKLE_PRIVATE_ED_KEY --repo "$REPO" < "$TMP"
echo "Set SPARKLE_PRIVATE_ED_KEY on $REPO"
