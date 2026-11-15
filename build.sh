#!/bin/sh
# Builds .build/Notchkeeper.app with plain swiftc: SwiftPM's manifest library is broken in this Command Line Tools install.
# arm64 only: every Mac with a notch is Apple silicon.
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-0.1.0}
APP=.build/Notchkeeper.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/hooks"
swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Sources/Notchkeeper/*.swift -o "$APP/Contents/MacOS/Notchkeeper"
cp hooks/notchkeeper-hook.sh hooks/notchkeeper-approve.sh "$APP/Contents/Resources/hooks/"
cp assets/Notchkeeper.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Notchkeeper</string>
  <key>CFBundleIdentifier</key><string>io.github.thevahidal.notchkeeper</string>
  <key>CFBundleExecutable</key><string>Notchkeeper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Notchkeeper</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Notchkeeper focuses the terminal tab an agent runs in, and types your replies into it.</string>
</dict>
</plist>
EOF

# Ad-hoc signature: not a Developer ID, but keeps the bundle consistent so macOS can track its permissions.
codesign --force --sign - "$APP"
echo "Built $APP"
