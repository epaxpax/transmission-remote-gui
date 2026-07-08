#!/usr/bin/env bash
#
# Builds the "Transmission Remote GUI.app" bundle from the SwiftPM release binary.
#
# There is no full Xcode on this machine (only Command Line Tools), so the .app bundle
# is assembled by hand: release build → bundle skeleton → binary + .icns + Info.plist →
# ad-hoc codesign. The result: dist/Transmission Remote GUI.app (can be dragged into /Applications).
#
# Usage:
#   Scripts/build-app.sh            # just the .app
#   Scripts/build-app.sh --dmg      # + portable .dmg
#
set -euo pipefail

APP_NAME="Transmission Remote GUI"   # displayed name + .app filename (with spaces)
PRODUCT="TransmissionRemoteGUI"      # SwiftPM target + binary filename (no spaces)
BUNDLE_ID="io.github.epaxpax.TransmissionRemoteGUI"   # app identity (reverse-DNS)
VERSION="0.1.3"        # CFBundleShortVersionString (pre-release: developer testing only)
BUILD="1"              # CFBundleVersion (build number)
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAKE_DMG=0
[ "${1:-}" = "--dmg" ] && MAKE_DMG=1

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Release build ($PRODUCT)…"
swift build -c release --product "$PRODUCT"
BIN="$ROOT/.build/release/$PRODUCT"
[ -x "$BIN" ] || { echo "ERROR: binary not found: $BIN" >&2; exit 1; }

echo "==> Bundle skeleton…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"

echo "==> Icon (.icns)…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

echo "==> Info.plist…"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${PRODUCT}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing…"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Done: $APP"

if [ "$MAKE_DMG" -eq 1 ]; then
    echo "==> DMG packaging…"
    DMG="$DIST/$APP_NAME.dmg"
    rm -f "$DMG"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "==> Done: $DMG"
fi

echo
echo "Install:  drag \"$APP_NAME.app\" into the /Applications folder."
echo "First launch (because of the ad-hoc signature): right-click → Open, then Open."
