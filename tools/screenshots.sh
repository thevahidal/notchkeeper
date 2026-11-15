#!/bin/sh
# Renders docs/img/*.png from the app's own views with sample data.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build docs/img
swiftc -swift-version 5 -target arm64-apple-macosx14.0 $(ls Sources/Ping/*.swift | grep -v main.swift) tools/screenshots.swift -parse-as-library -o .build/screenshots
.build/screenshots docs/img
