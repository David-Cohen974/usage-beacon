#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <UsageBeacon.app> <output.dmg>" >&2
  exit 2
fi

app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
output_path="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

if [[ ! -d "$app_path" ]]; then
  echo "Application not found: $app_path" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-dmg.XXXXXX")"
trap 'find "$work_dir" -depth -delete 2>/dev/null || true' EXIT

staging_dir="$work_dir/UsageBeacon"
mkdir -p "$staging_dir"
ditto --norsrc "$app_path" "$staging_dir/UsageBeacon.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$output_path"
hdiutil create \
  -volname "UsageBeacon" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -fs HFS+ \
  -ov \
  "$output_path"

echo "Created $output_path"
