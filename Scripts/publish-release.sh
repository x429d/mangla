#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${MANGLA_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
TAG="v$VERSION"
ASSET_DIR="${1:-$ROOT/dist}"
ZIP="$ASSET_DIR/Mangla-$VERSION-macos.zip"
CHECKSUM="$ZIP.sha256"
REPOSITORY="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
TARGET="${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"

if [[ ! -f "$ZIP" || ! -f "$CHECKSUM" ]]; then
    echo "error: release assets are missing in $ASSET_DIR" >&2
    exit 1
fi

if gh api "repos/$REPOSITORY/git/ref/tags/$TAG" >/dev/null 2>&1; then
    echo "==> $TAG already exists; publishing nightly"
    gh release delete nightly --cleanup-tag -y >/dev/null 2>&1 || true
    gh api -X DELETE "repos/$REPOSITORY/git/refs/tags/nightly" >/dev/null 2>&1 || true
    gh release create nightly "$ZIP" "$CHECKSUM" \
        --prerelease \
        --target "$TARGET" \
        --title "Nightly" \
        --notes "Automated build from $TARGET."
else
    echo "==> creating $TAG"
    NOTES_FILE="$(mktemp "${TMPDIR:-/tmp}mangla-notes.XXXXXX")"
    trap 'rm -f "$NOTES_FILE"' EXIT
    "$ROOT/Scripts/release-notes.sh" "$VERSION" > "$NOTES_FILE"
    gh release create "$TAG" "$ZIP" "$CHECKSUM" \
        --target "$TARGET" \
        --title "Mangla $VERSION" \
        --notes-file "$NOTES_FILE"
fi
