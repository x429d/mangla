#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${MANGLA_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
APP="$ROOT/Mangla.app"
DIST="$ROOT/dist"
ZIP_NAME="Mangla-$VERSION-macos.zip"
ZIP="$DIST/$ZIP_NAME"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP does not exist; run Scripts/build-app.sh first" >&2
    exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$ZIP"
(
    cd "$DIST"
    shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
)

echo "==> packaged $ZIP"
echo "==> checksum $ZIP.sha256"
