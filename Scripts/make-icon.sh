#!/usr/bin/env bash
set -euo pipefail

# Builds Resources/AppIcon.icns from Scripts/make-icon.swift.
# Usage: Scripts/make-icon.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Resources/AppIcon.icns"
TMP="$(mktemp -d -t mangla-icon)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ rendering 1024 px master"
swift "$ROOT/Scripts/make-icon.swift" "$TMP/icon_1024.png"

echo "▸ building iconset"
mkdir -p "$TMP/AppIcon.iconset"
while IFS=: read -r size name; do
    sips -z "$size" "$size" "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/$name" >/dev/null
done <<'SIZES'
16:icon_16x16.png
32:icon_16x16@2x.png
32:icon_32x32.png
64:icon_32x32@2x.png
128:icon_128x128.png
256:icon_128x128@2x.png
256:icon_256x256.png
512:icon_256x256@2x.png
512:icon_512x512.png
1024:icon_512x512@2x.png
SIZES

echo "▸ packing icns"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT"
echo "  wrote $OUT"
