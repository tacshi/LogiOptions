#!/usr/bin/env bash
# Re-enable official Logi Options+ agents after LogiOptions development.
set -euo pipefail

UID_NUM="$(id -u)"
GUI="gui/${UID_NUM}"

bootstrap() {
  local plist="$1"
  if [[ -f "$plist" ]]; then
    echo "bootstrap $plist"
    launchctl bootstrap "$GUI" "$plist" 2>/dev/null || launchctl load -w "$plist" 2>/dev/null || true
  fi
}

echo "Starting Logi Options+…"
bootstrap "/Library/LaunchAgents/com.logi.optionsplus.plist"
bootstrap "/Library/LaunchAgents/com.logi.optionsplus.logivoice.plist"

sleep 1
pgrep -lf 'logioptionsplus' || echo "No process yet — open /Applications/logioptionsplus.app if needed."
echo "Done."
