#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."
ROOT_DIR="$PWD"
APP_PATH="/Applications/UsageBeacon.app"
WIDGET_PATH="$APP_PATH/Contents/PlugIns/UsageBeaconWidget.appex"

# Finish and verify the candidate before interrupting the installed app.
"$ROOT_DIR/Scripts/build-app.sh" debug
STAGING_DIR="$(mktemp -d "/Applications/.usagebeacon-install.XXXXXX")"
ditto -x -k "$ROOT_DIR/dist/UsageBeacon.zip" "$STAGING_DIR"
codesign --verify --deep --strict "$STAGING_DIR/UsageBeacon.app"

pkill -x UsageBeacon 2>/dev/null || true
if [[ -d "$APP_PATH" ]]; then
  mv "$APP_PATH" "$STAGING_DIR/PreviousUsageBeacon.app"
fi
if ! mv "$STAGING_DIR/UsageBeacon.app" "$APP_PATH"; then
  if [[ -d "$STAGING_DIR/PreviousUsageBeacon.app" ]]; then
    mv "$STAGING_DIR/PreviousUsageBeacon.app" "$APP_PATH"
  fi
  echo "Install failed; restored the previous app when available." >&2
  exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
# PlugInKit requires the containing app to be registered first.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
pluginkit -a "$WIDGET_PATH"
pluginkit -e use -i com.rekindle.usagebeacon.widget
pkill -x UsageBeaconWidget 2>/dev/null || true
open -n "$APP_PATH"
echo "Installed candidate. Rollback copy: $STAGING_DIR/PreviousUsageBeacon.app"
