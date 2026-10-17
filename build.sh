#!/bin/bash
# Builds "build/Claude Touch Bar.app" with plain swiftc (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Claude Touch Bar.app"
mkdir -p build
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o build/ClaudeTouchBar

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp build/ClaudeTouchBar "$APP/Contents/MacOS/"
# A stable local certificate keeps the Accessibility permission across
# rebuilds; ad-hoc signing changes identity every build.
IDENTITY="ClaudeTouchBar Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1
else
    codesign --force --sign - "$APP" >/dev/null
fi
echo "Hotovo: $APP"
