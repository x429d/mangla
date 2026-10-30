#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
CHANGELOG="$ROOT/CHANGELOG.md"

if [[ ! -f "$CHANGELOG" ]]; then
    echo "See CHANGELOG.md."
    exit 0
fi

NOTES="$(
    awk -v version="$VERSION" '
        $0 ~ "^## \\[" version "\\]" { inside = 1; next }
        inside && /^## \[/ { exit }
        inside { print }
    ' "$CHANGELOG"
)"

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
    echo "See CHANGELOG.md for the $VERSION release notes."
else
    printf '%s\n' "$NOTES"
fi
