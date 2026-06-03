#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT"
APP_NAME="Floaty"
APP_DIR="$ROOT/outputs/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
NO_OPEN=0
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --no-open) NO_OPEN=1 ;;
    --verify) VERIFY=1 ;;
  esac
done

if pgrep -x "SpotifyLyricsPiP" >/dev/null 2>&1; then
  pkill -x "SpotifyLyricsPiP" || true
  sleep 0.3
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" || true
  sleep 0.3
fi

cd "$PACKAGE_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Floaty</string>
  <key>CFBundleIdentifier</key>
  <string>com.vyctorbrzezowski.floaty</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Floaty</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Reads the current Spotify song and playback position to show synced lyrics in a floating window.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

if [[ "$NO_OPEN" == "0" ]]; then
  /usr/bin/open -n "$APP_DIR"
fi

if [[ "$VERIFY" == "1" ]]; then
  sleep 1
  if [[ "$NO_OPEN" == "0" ]]; then
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running from $APP_DIR"
  else
    echo "$APP_NAME is ready at $APP_DIR"
  fi
  codesign --verify --deep --strict "$APP_DIR"
fi
