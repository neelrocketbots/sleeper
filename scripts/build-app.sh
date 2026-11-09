#!/bin/sh
# Builds Sleeper.app (release, ad-hoc signed) into .build/app.
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=.build/app/Sleeper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sleeper "$APP/Contents/MacOS/Sleeper"
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
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
