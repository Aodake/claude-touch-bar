#!/bin/bash
# Builds the app, copies it to ~/Applications, enables start at login and launches it.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
DEST="$HOME/Applications/Claude Touch Bar.app"
pkill -x ClaudeTouchBar 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "build/Claude Touch Bar.app" "$DEST"

PLIST="$HOME/Library/LaunchAgents/local.ClaudeTouchBar.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>local.ClaudeTouchBar</string>
	<key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/ClaudeTouchBar</string><string>--background</string></array>
	<key>RunAtLoad</key><true/>
	<key>ProcessType</key><string>Interactive</string>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PL

open "$DEST"
echo "Nainstalováno do $DEST a spuštěno. Po přihlášení se spustí samo."
