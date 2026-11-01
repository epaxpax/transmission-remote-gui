#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Optional SwiftPM flags, e.g. --disable-sandbox --build-system native in restricted environments.
swift build -c release --product TransmissionRemoteGUI "$@"
BIN_DIR="$(swift build -c release --show-bin-path "$@")"
COMPILER_FLAGS=(-parse-as-library -swift-version 6)
for flag in "$@"; do
    if [[ "$flag" == --disable-sandbox ]]; then COMPILER_FLAGS+=(-disable-sandbox); fi
done
swiftc "${COMPILER_FLAGS[@]}" -I "$BIN_DIR/Modules" \
    Sources/TransmissionRemoteGUI/Model/*.swift Sources/TransmissionRemoteGUI/AppIcon.swift \
    Scripts/test-add-confirmation.swift \
    "$BIN_DIR"/TransmissionKit.build/*.o "$BIN_DIR"/TransmissionLocalization.build/*.o \
    -o .build/AddConfirmationTests

TEST_HOME="$(mktemp -d "$PWD/.build/confirmation-test-home.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
CFFIXED_USER_HOME="$TEST_HOME" .build/AddConfirmationTests
