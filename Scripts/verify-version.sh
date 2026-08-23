#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version-or-tag>" >&2
  exit 2
fi

requested="${1#v}"
marketing_version="${requested%%-*}"

if [[ ! "$requested" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release tag/version: $1" >&2
  echo "Expected v1.2.3 or v1.2.3-beta.1" >&2
  exit 1
fi

configured_version="$({
  sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*//p' Config/Version.xcconfig
} | tail -1 | xargs)"

if [[ "$configured_version" != "$marketing_version" ]]; then
  echo "Release version mismatch." >&2
  echo "Tag requests: $marketing_version" >&2
  echo "Config/Version.xcconfig contains: $configured_version" >&2
  exit 1
fi

echo "$requested"
