#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app/macos/LogiOptionsDaemon"

# Ensure official Options+ is not holding HID++
"$ROOT/tools/stop_options_plus.sh" || true

echo "Building LogiOptionsDaemon…"
swift build -c release 2>&1
BIN="$(swift build -c release --show-bin-path)/LogiOptionsDaemon"
echo "Running $BIN"
exec "$BIN" "$@"
