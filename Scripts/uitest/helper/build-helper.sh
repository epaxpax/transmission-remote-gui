#!/usr/bin/env bash
# Builds ~/Applications/TRGUI UITest Helper.app. Build it ONCE: the Accessibility grant is tied
# to the ad-hoc signature, so a rebuild needs the toggle to be switched on again.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="/Applications/TRGUI UITest Helper.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/helper" "$HERE/main.swift"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>io.github.epaxpax.TRGUIUITestHelper</string>
    <key>CFBundleName</key><string>TRGUI UITest Helper</string>
    <key>CFBundleExecutable</key><string>helper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Drives Transmission Remote GUI in UI tests.</string>
</dict></plist>
PLIST
codesign --force -s - --identifier io.github.epaxpax.TRGUIUITestHelper "$APP"
echo "$APP"
