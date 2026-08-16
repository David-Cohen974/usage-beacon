#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."
ROOT_DIR="$PWD"
APP_PATH="$ROOT_DIR/dist/UsageBeacon.app"

pkill -x UsageBeacon 2>/dev/null || true
sleep 1

"$ROOT_DIR/Scripts/build-app.sh" debug
open -n "$APP_PATH"
