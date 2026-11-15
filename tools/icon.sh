#!/bin/sh
# Renders assets/Ping.icns from tools/icon.swift.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build/icon.iconset assets
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library tools/icon.swift -o .build/icon
.build/icon .build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size .build/icon-1024.png --out .build/icon.iconset/icon_${size}x${size}.png >/dev/null
  sips -z $((size * 2)) $((size * 2)) .build/icon-1024.png --out .build/icon.iconset/icon_${size}x${size}@2x.png >/dev/null
done
iconutil -c icns .build/icon.iconset -o assets/Ping.icns
cp .build/icon-1024.png docs/img/icon.png
echo "Wrote assets/Ping.icns"
