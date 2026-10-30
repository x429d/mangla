#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
VERSION="${MANGLA_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="${MANGLA_BUILD_NUMBER:-1}"
APP="$ROOT/Mangla.app"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version '$VERSION'" >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: invalid build number '$BUILD_NUMBER'" >&2
    exit 1
fi

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Mangla"
if [[ ! -x "$BIN" ]]; then
    echo "error: binary not found at $BIN" >&2
    exit 1
fi

echo "==> assembling Mangla.app $VERSION ($BUILD_NUMBER)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mangla"
chmod +x "$APP/Contents/MacOS/Mangla"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ru</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>Mangla</string>
    <key>CFBundleIdentifier</key>
    <string>com.mangla.reader</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mangla</string>
    <key>CFBundleDisplayName</key>
    <string>Mangla</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.entertainment</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signing is enough for local use and GitHub Releases. Distribution
# through the App Store or notarization needs a Developer ID identity.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> done: $APP"
echo "    open \"$APP\""
