#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."
ROOT_DIR="$PWD"
CONFIGURATION="${1:-release}"
APP_NAME="UsageBeacon"
PRODUCT_NAME="UsageBeaconApp"
BUNDLE_IDENTIFIER="${USAGEBEACON_BUNDLE_IDENTIFIER:-com.rekindle.usagebeacon}"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-build.XXXXXX")"
TEMP_APP_DIR="$BUILD_ROOT/$APP_NAME.app"
CONTENTS_DIR="$TEMP_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

swift build -c "$CONFIGURATION" --jobs 1
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --jobs 1)"
BIN_PATH="$BIN_DIR/$PRODUCT_NAME"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
cp "$APP_ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>UsageBeacon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>UsageBeacon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>UsageBeacon reads selected holiday and vacation calendars to calculate working-day budgets.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>UsageBeacon reads selected holiday and vacation calendars to calculate working-day budgets.</string>
</dict>
</plist>
EOF

xattr -cr "$TEMP_APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$TEMP_APP_DIR" >/dev/null
codesign --verify --deep --strict "$TEMP_APP_DIR"

rm -rf "$APP_DIR"
mkdir -p "$DIST_DIR"
ditto --norsrc "$TEMP_APP_DIR" "$APP_DIR"
echo "Built $APP_DIR"
