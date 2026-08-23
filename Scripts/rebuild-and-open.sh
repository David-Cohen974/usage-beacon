#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."
ROOT_DIR="$PWD"
APP_PATH="/Applications/UsageBeacon.app"
WIDGET_PATH="$APP_PATH/Contents/PlugIns/UsageBeaconWidget.appex"

pkill -x UsageBeacon 2>/dev/null || true
sleep 1

"$ROOT_DIR/Scripts/build-app.sh" debug
pluginkit -r "$WIDGET_PATH" 2>/dev/null || true
rm -rf "$APP_PATH"
ditto -x -k "$ROOT_DIR/dist/UsageBeacon.zip" /Applications
xattr -cr "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
pluginkit -a "$WIDGET_PATH"
pluginkit -e use -i com.rekindle.usagebeacon.widget
open -n "$APP_PATH"
