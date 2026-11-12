#!/bin/sh
# Builds Sleeper.app (release, ad-hoc signed) into .build/app.
set -eu
cd "$(dirname "$0")/.."
# The version: VERSION in the environment, else the newest tag (v1.2.3 → 1.2.3), else 0.0.0.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)}"
VERSION="${VERSION#v}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
swift build -c release
APP=.build/app/Sleeper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sleeper "$APP/Contents/MacOS/Sleeper"
# The painted art (SwiftPM resource bundle) goes where Bundle.module looks for it in an app.
cp -R .build/release/Sleeper_SleeperApp.bundle "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sleeper</string>
  <key>CFBundleDisplayName</key><string>Sleeper</string>
  <key>CFBundleIdentifier</key><string>dev.neel.sleeper</string>
  <key>CFBundleExecutable</key><string>Sleeper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
