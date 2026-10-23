#!/usr/bin/env bash
# Builds MenuTerm.app into ./build using Swift Package Manager (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="MenuTerm"
BUNDLE_ID="com.local.menuterm"
VERSION="${VERSION:-0.1.0}"

swift build -c "$CONFIG" 2>&1 | grep -v "ld: warning" || true
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 1; }

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# App icon: the binary renders its own icon (AppIcon.swift), iconutil packs it into .icns.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/$APP_NAME" --write-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS keeps window-frame autosave and permissions stable across rebuilds.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $APP"
