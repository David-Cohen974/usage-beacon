#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <generate_appcast|generate_keys|sign_update>" >&2
  exit 2
fi

tool_name="$1"

if [[ -n "${SPARKLE_TOOLS_DIR:-}" && -x "$SPARKLE_TOOLS_DIR/$tool_name" ]]; then
  echo "$SPARKLE_TOOLS_DIR/$tool_name"
  exit 0
fi

if [[ -n "${SOURCE_PACKAGES_DIR_PATH:-}" ]]; then
  candidate="$SOURCE_PACKAGES_DIR_PATH/artifacts/sparkle/Sparkle/bin/$tool_name"
  if [[ -x "$candidate" ]]; then
    echo "$candidate"
    exit 0
  fi
fi

candidate="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" \
    -type f -perm -111 -print 2>/dev/null \
    | head -1
)"
if [[ -n "$candidate" ]]; then
  echo "$candidate"
  exit 0
fi

echo "Could not find Sparkle tool '$tool_name'. Resolve/build the Xcode project first." >&2
exit 1
