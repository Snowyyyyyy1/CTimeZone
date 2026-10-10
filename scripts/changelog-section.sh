#!/bin/bash
# Print the CHANGELOG.md section for one version, without its heading.
# Fails when the version has no entry, so a release cannot ship unnoted.
#
# Usage: scripts/changelog-section.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/changelog-section.sh <version>}"
SECTION="$(awk -v v="$VERSION" '
  /^## / { if (found) exit; if ($2 == v) { found = 1; next } }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [ -z "$(echo "$SECTION" | tr -d '[:space:]')" ]; then
  echo "CHANGELOG.md has no entry for $VERSION" >&2
  exit 1
fi
printf '%s\n' "$SECTION"
