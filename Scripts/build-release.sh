#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."
ROOT_DIR="$PWD"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <marketing-version> <build-number> [asset-version]" >&2
  exit 2
fi

marketing_version="$1"
build_number="$2"
asset_version="${3:-$marketing_version}"
identity="${CODE_SIGN_IDENTITY:-}"

if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
      | head -1
  )"
fi

if [[ -z "$identity" || "$identity" == "-" ]]; then
  echo "A Developer ID Application identity is required for a release." >&2
  exit 1
fi

notary_arguments=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  notary_arguments+=(--keychain-profile "$NOTARYTOOL_PROFILE")
elif [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  notary_arguments+=(
    --key "$APPLE_API_KEY_PATH"
    --key-id "$APPLE_API_KEY_ID"
    --issuer "$APPLE_API_ISSUER_ID"
  )
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  notary_arguments+=(
    --apple-id "$APPLE_ID"
    --team-id "$APPLE_TEAM_ID"
    --password "$APPLE_APP_PASSWORD"
  )
else
  echo "Notarization credentials are missing." >&2
  echo "Set NOTARYTOOL_PROFILE, App Store Connect API credentials, or Apple ID credentials." >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-release.XXXXXX")"
trap 'find "$work_dir" -depth -delete 2>/dev/null || true' EXIT

MARKETING_VERSION="$marketing_version" \
BUILD_NUMBER="$build_number" \
CODE_SIGN_IDENTITY="$identity" \
  "$ROOT_DIR/Scripts/build-app.sh" release

unsigned_ticket_zip="$ROOT_DIR/dist/UsageBeacon.zip"
xcrun notarytool submit "$unsigned_ticket_zip" "${notary_arguments[@]}" --wait

ditto -x -k "$unsigned_ticket_zip" "$work_dir/app"
app_path="$work_dir/app/UsageBeacon.app"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
"$ROOT_DIR/Scripts/verify-app-launch.sh" "$app_path"

update_archive="$ROOT_DIR/dist/UsageBeacon-$asset_version.zip"
rm -f "$update_archive"
ditto -c -k --norsrc --keepParent "$app_path" "$update_archive"

dmg_path="$ROOT_DIR/dist/UsageBeacon-$asset_version.dmg"
"$ROOT_DIR/Scripts/create-dmg.sh" "$app_path" "$dmg_path"
codesign --force --timestamp --sign "$identity" "$dmg_path"
xcrun notarytool submit "$dmg_path" "${notary_arguments[@]}" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

echo "Release artifacts:"
echo "  $update_archive"
echo "  $dmg_path"
