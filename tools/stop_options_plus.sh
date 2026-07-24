#!/usr/bin/env bash
# Stop official Logi Options+ agents so LogiOptions can own HID++.
set -euo pipefail

UID_NUM="$(id -u)"
GUI="gui/${UID_NUM}"

stop_plist() {
  local plist="$1"
  if [[ -f "$plist" ]]; then
    echo "bootout $plist"
    launchctl bootout "$GUI" "$plist" 2>/dev/null || true
  fi
}

echo "Stopping Logi Options+ (user session)…"
stop_plist "/Library/LaunchAgents/com.logi.optionsplus.plist"
stop_plist "/Library/LaunchAgents/com.logi.optionsplus.logivoice.plist"

# Residual processes
for name in logioptionsplus_agent logioptionsplus_logivoice logioptionsplus; do
  if pgrep -x "$name" >/dev/null 2>&1; then
    echo "killall $name"
    killall "$name" 2>/dev/null || true
  fi
done

sleep 0.5
# Agent must be gone for HID++ ownership. Updater (root) is optional noise.
if pgrep -x 'logioptionsplus_agent' >/dev/null 2>&1 || pgrep -x 'logioptionsplus' >/dev/null 2>&1; then
  echo "Warning: Options+ agent still running:"
  pgrep -lf 'logioptionsplus' || true
  killall -9 logioptionsplus_agent logioptionsplus logioptionsplus_logivoice 2>/dev/null || true
  sleep 0.3
fi

if pgrep -x 'logioptionsplus_agent' >/dev/null 2>&1; then
  echo "ERROR: could not stop logioptionsplus_agent"
  exit 1
fi

if pgrep -x 'logioptionsplus_updater' >/dev/null 2>&1; then
  echo "Note: updater still running (root). Optional: sudo launchctl bootout system /Library/LaunchDaemons/com.logi.optionsplus.updater.plist"
fi

echo "Options+ agents stopped. Mouse still works as a standard HID mouse."
