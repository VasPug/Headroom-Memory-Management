#!/bin/bash
# Builds Headroom.app. Run ./build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Headroom

APP="build/Headroom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Headroom" "$APP/Contents/MacOS/Headroom"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Headroom</string>
  <key>CFBundleDisplayName</key><string>Headroom</string>
  <key>CFBundleIdentifier</key><string>io.github.vaspug.headroom</string>
  <key>CFBundleExecutable</key><string>Headroom</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Background agent: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS treats it as a stable identity across rebuilds.
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Headroom 2>/dev/null || true
  rm -rf /Applications/Headroom.app
  cp -R "$APP" /Applications/Headroom.app

  PLIST_PATH="$HOME/Library/LaunchAgents/io.github.vaspug.headroom.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST_PATH" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>io.github.vaspug.headroom</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/Headroom.app/Contents/MacOS/Headroom</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
AGENT
  launchctl bootout "gui/$(id -u)/io.github.vaspug.headroom" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
  echo "Installed to /Applications and started at login."
fi
