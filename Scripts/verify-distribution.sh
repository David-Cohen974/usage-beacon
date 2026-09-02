#!/usr/bin/env bash
set -euo pipefail

metadata_url="${1:-https://david-cohen974.github.io/usage-beacon/latest.json}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-verification.XXXXXX")"
mount_dir="$work_dir/mount"
mounted="false"

cleanup() {
  if [[ "$mounted" == "true" ]]; then
    hdiutil detach "$mount_dir" -quiet 2>/dev/null || true
  fi
  find "$work_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

metadata_path="$work_dir/latest.json"
appcast_path="$work_dir/appcast.xml"
dmg_path="$work_dir/UsageBeacon.dmg"

curl --fail --location --silent --show-error "$metadata_url" --output "$metadata_path"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$metadata_path")"
download_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["downloadUrl"])' "$metadata_path")"
minimum_macos="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["minimumMacOS"])' "$metadata_path")"
appcast_url="${metadata_url%/latest.json}/appcast.xml"

test -n "$version"
test -n "$download_url"
curl --fail --location --silent --show-error "$appcast_url" --output "$appcast_path"
xmllint --noout "$appcast_path"
grep -q 'sparkle:edSignature=' "$appcast_path"
grep -q 'sparkle-signatures:' "$appcast_path"
grep -Eq "<sparkle:shortVersionString>$version</sparkle:shortVersionString>|sparkle:shortVersionString=\"$version\"" "$appcast_path"

curl --fail --location --silent --show-error "$download_url" --output "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

mkdir -p "$mount_dir"
hdiutil attach "$dmg_path" -mountpoint "$mount_dir" -nobrowse -readonly -quiet
mounted="true"
app_path="$mount_dir/UsageBeacon.app"
test -d "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
"${BASH_SOURCE[0]%/*}/verify-app-launch.sh" "$app_path"

test "$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")" = "$version"
test "$(plutil -extract LSMinimumSystemVersion raw "$app_path/Contents/Info.plist")" = "$minimum_macos"
test "$(plutil -extract SUFeedURL raw "$app_path/Contents/Info.plist")" = "$appcast_url"
test "$(plutil -extract SUPublicEDKey raw "$app_path/Contents/Info.plist")" = "TsvqpRp6P1+qRLzm/ei62YSGnZvsp//bdQITGnVdm8Y="
test -d "$app_path/Contents/Frameworks/Sparkle.framework"

echo "Verified UsageBeacon $version from $download_url"
echo "Developer ID, notarization ticket, launchability, Sparkle framework, appcast, and Ed25519 metadata are present."
