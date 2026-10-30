#!/usr/bin/env bash
set -euo pipefail

# Prints the newest installed Xcode whose Swift compiler reports Swift 6.
# The workflow selects it with xcode-select; local runs only inspect it.
while IFS= read -r app; do
    swift_bin="$app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    [[ -x "$swift_bin" ]] || continue
    version="$("$swift_bin" --version 2>/dev/null || true)"
    if [[ "$version" == *"Swift version 6"* ]]; then
        echo "$app/Contents/Developer"
        exit 0
    fi
done < <(find /Applications -maxdepth 1 -name 'Xcode*.app' -print | sort -r)

echo "error: no Xcode with Swift 6 found in /Applications" >&2
exit 1
