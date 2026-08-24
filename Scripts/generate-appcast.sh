#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."

if [[ $# -lt 5 || $# -gt 6 ]]; then
  echo "Usage: $0 <archives-dir> <output-appcast> <tag> <build-number> <stable|beta> [repository]" >&2
  exit 2
fi

archives_dir="$(cd "$1" && pwd)"
output_appcast="$2"
tag="$3"
build_number="$4"
channel="$5"
repository="${6:-${GITHUB_REPOSITORY:-David-Cohen974/usage-beacon}}"

case "$channel" in
  stable|beta) ;;
  *)
    echo "Channel must be stable or beta." >&2
    exit 1
    ;;
esac

generate_appcast="$("$SCRIPT_DIR/find-sparkle-tool.sh" generate_appcast)"
arguments=(
  --account com.rekindle.usagebeacon
  --download-url-prefix "https://github.com/$repository/releases/download/$tag/"
  --embed-release-notes
  --full-release-notes-url "https://david-cohen974.github.io/usage-beacon/changelog/"
  --link "https://david-cohen974.github.io/usage-beacon/"
  --maximum-versions 10
  --maximum-deltas 5
  --versions "$build_number"
)

if [[ "$channel" == "beta" ]]; then
  arguments+=(--channel beta)
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" \
    | "$generate_appcast" --ed-key-file - "${arguments[@]}" "$archives_dir"
else
  "$generate_appcast" "${arguments[@]}" "$archives_dir"
fi

generated_appcast="$archives_dir/appcast.xml"
if [[ ! -f "$generated_appcast" ]]; then
  echo "Sparkle did not generate $generated_appcast" >&2
  exit 1
fi

xmllint --noout "$generated_appcast"
if ! grep -Eq "sparkle:version=\"$build_number\"|<sparkle:version>$build_number</sparkle:version>" "$generated_appcast"; then
  echo "Generated appcast does not contain build $build_number." >&2
  exit 1
fi
if ! grep -q 'sparkle:edSignature=' "$generated_appcast"; then
  echo "Generated appcast does not contain an Ed25519 archive signature." >&2
  exit 1
fi
if ! grep -q 'sparkle-signatures:' "$generated_appcast"; then
  echo "Generated appcast is not signed." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_appcast")"
ditto --norsrc "$generated_appcast" "$output_appcast"
echo "Generated $output_appcast"
