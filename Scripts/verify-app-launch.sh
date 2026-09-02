#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-app>" >&2
  exit 2
fi

app_path="$1"
executable="$app_path/Contents/MacOS/UsageBeacon"

if [[ ! -x "$executable" ]]; then
  echo "UsageBeacon executable is missing or not executable: $executable" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-launch.XXXXXX")"
launch_log="$work_dir/launch.log"
launch_pid=""

cleanup() {
  if [[ -n "$launch_pid" ]] && kill -0 "$launch_pid" 2>/dev/null; then
    kill -TERM "$launch_pid" 2>/dev/null || true
    wait "$launch_pid" 2>/dev/null || true
  fi
  find "$work_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

"$executable" >"$launch_log" 2>&1 &
launch_pid=$!

for _ in {1..15}; do
  sleep 0.2
  if ! kill -0 "$launch_pid" 2>/dev/null; then
    set +e
    wait "$launch_pid"
    exit_status=$?
    set -e
    echo "UsageBeacon exited during its launch smoke test (status $exit_status)." >&2
    if [[ -s "$launch_log" ]]; then
      cat "$launch_log" >&2
    fi
    exit 1
  fi
done

echo "UsageBeacon remained running for the launch smoke test."
