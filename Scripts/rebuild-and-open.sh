#!/usr/bin/env bash
set -euo pipefail
cd "${BASH_SOURCE[0]%/*}/.."
ROOT_DIR="$PWD"
APP_PATH="/Applications/UsageBeacon.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# A prepared, notarized archive can be supplied by the release workflow.
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [verified-release.zip]" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  ARCHIVE="$1"
else
  "$ROOT_DIR/Scripts/build-app.sh" release
  ARCHIVE="$ROOT_DIR/dist/UsageBeacon.zip"
fi
STAGING_DIR="$(mktemp -d "/Applications/.usagebeacon-install.XXXXXX")"
installed=false
committed=false
cleanup() {
  if [[ "$installed" == true && "$committed" == false ]]; then
    pkill -x UsageBeacon 2>/dev/null || true
    rm -rf "$APP_PATH"
    if [[ -d "$STAGING_DIR/PreviousUsageBeacon.app" ]]; then
      mv "$STAGING_DIR/PreviousUsageBeacon.app" "$APP_PATH"
      "$LSREGISTER" -f "$APP_PATH" || true
      pluginkit -a "$APP_PATH/Contents/PlugIns/UsageBeaconWidget.appex" || true
      open "$APP_PATH" || true
    fi
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto -x -k "$ARCHIVE" "$STAGING_DIR"
codesign --verify --deep --strict "$STAGING_DIR/UsageBeacon.app"
test "$(plutil -extract CFBundleIdentifier raw "$STAGING_DIR/UsageBeacon.app/Contents/Info.plist")" = com.rekindle.usagebeacon
test -d "$STAGING_DIR/UsageBeacon.app/Contents/PlugIns/UsageBeaconWidget.appex"
# An ad-hoc signature cannot authorize this team-prefixed widget app group.
for candidate in "$STAGING_DIR/UsageBeacon.app" "$STAGING_DIR/UsageBeacon.app/Contents/PlugIns/UsageBeaconWidget.appex"; do
  if ! codesign -dv "$candidate" 2>&1 | grep '^TeamIdentifier=Y3XM9Q3AZT$' >/dev/null; then
    echo "Install requires a Developer ID signed app and widget from the UsageBeacon team." >&2
    exit 1
  fi
done
pkill -x UsageBeacon 2>/dev/null || true
pkill -x UsageBeaconWidget 2>/dev/null || true
if [[ -d "$APP_PATH" ]]; then
  "$LSREGISTER" -u "$APP_PATH" || true
  mv "$APP_PATH" "$STAGING_DIR/PreviousUsageBeacon.app"
fi
installed=true
mv "$STAGING_DIR/UsageBeacon.app" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
"$ROOT_DIR/Scripts/verify-app-launch.sh" "$APP_PATH"
"$LSREGISTER" -f "$APP_PATH"
pluginkit -a "$APP_PATH/Contents/PlugIns/UsageBeaconWidget.appex"
pluginkit -e use -i com.rekindle.usagebeacon.widget
committed=true
open "$APP_PATH"
echo "Installed verified Release build at $APP_PATH; temporary rollback app removed."
