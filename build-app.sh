#!/bin/bash
# Headroom build / install / uninstall.
#
#   ./build-app.sh              build build/Headroom.app
#   ./build-app.sh --install    install to /Applications and start at login
#   ./build-app.sh --uninstall  remove it and everything it stored
set -euo pipefail
cd "$(dirname "$0")"

LABEL=io.github.vaspug.headroom
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
    sleep 1
  done
  pkill -x Headroom 2>/dev/null || true
  rm -f "$AGENT_PLIST"
  rm -rf /Applications/Headroom.app
  rm -rf "$HOME/Library/Application Support/Headroom"
  defaults delete "$LABEL" 2>/dev/null || true
  echo "Headroom removed, including everything it learned."
  exit 0
fi

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
  # Stop the agent BEFORE swapping the bundle. KeepAlive would otherwise
  # relaunch it from a half-replaced app directory.
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
    sleep 1
  done
  pkill -x Headroom 2>/dev/null || true

  rm -rf /Applications/Headroom.app
  cp -R "$APP" /Applications/Headroom.app

  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT_PLIST" <<AGENT
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
  for attempt in 1 2 3; do
    if launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null; then break; fi
    [[ $attempt == 3 ]] && { echo "Could not register the login agent."; exit 1; }
    sleep 2
  done
  echo "Installed. Headroom is running and will start at login."
  echo "Look for the pill just right of your notch."
fi
