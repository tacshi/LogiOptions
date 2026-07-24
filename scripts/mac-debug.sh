#!/usr/bin/env bash
# Build a single runnable debug app into dist/
#
# Output (only artifact — no subfolders under dist/):
#   dist/LogiOptions.app
#
# The app embeds LogiOptionsDaemon under Contents/Helpers/ and starts it on launch.
#
# Signing (recommended for stable TCC / Accessibility grants):
#   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
#   ./scripts/mac-debug.sh
#
# Uses the same identity as mac-release.sh so macOS keeps Accessibility /
# Automation grants across rebuilds. Without DEVELOPER_ID_APPLICATION, falls
# back to ad-hoc signing (permissions will ask again after each rebuild).
#
# Usage (from repo root):
#   ./scripts/mac-debug.sh
#   open dist/LogiOptions.app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
DAEMON_DIR="$APP_DIR/macos/LogiOptionsDaemon"
DIST_DIR="$ROOT/dist"
PRODUCT_NAME="LogiOptions"
APP_DST="$DIST_DIR/${PRODUCT_NAME}.app"
BUNDLE_ID_APP="com.logioptions.app"
BUNDLE_ID_DAEMON="com.logioptions.daemon"
DEBUG_ENTITLEMENTS="$APP_DIR/macos/Runner/DebugProfile.entitlements"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

need flutter
need swift
need rsync

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

# Ensure log files exist for daemon stdout/stderr when launched from the app
: >> /tmp/logioptions.daemon.out.log
: >> /tmp/logioptions.daemon.err.log

echo "==> Building LogiOptionsDaemon (debug)"
(
  cd "$DAEMON_DIR"
  swift build -c debug
)
DAEMON_BIN="$(cd "$DAEMON_DIR" && swift build -c debug --show-bin-path)/LogiOptionsDaemon"
if [[ ! -x "$DAEMON_BIN" ]]; then
  echo "error: daemon binary missing at $DAEMON_BIN" >&2
  exit 1
fi

echo "==> Building Flutter macOS app (debug)"
(
  cd "$APP_DIR"
  flutter pub get
  flutter build macos --debug
)

APP_SRC=""
candidates=(
  "$APP_DIR/build/macos/Build/Products/Debug/${PRODUCT_NAME}.app"
  "$APP_DIR/build/macos/Build/Products/Debug/LogiOptions.app"
)
for c in "${candidates[@]}"; do
  if [[ -d "$c" ]]; then
    APP_SRC="$c"
    break
  fi
done
if [[ -z "$APP_SRC" ]]; then
  APP_SRC="$(find "$APP_DIR/build/macos/Build/Products/Debug" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1 || true)"
fi
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "error: could not find built .app under app/build/macos/Build/Products/Debug" >&2
  exit 1
fi

echo "==> Assembling $APP_DST"
# Clear previous dist contents so only the .app remains
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
rsync -a --delete "$APP_SRC/" "$APP_DST/"
# Keep dist/ free of Finder junk
rm -f "$DIST_DIR/.DS_Store" 2>/dev/null || true

# Embed daemon helper as a mini-bundle so TCC (Accessibility / Automation)
# can track com.logioptions.daemon separately from the UI.
HELPERS="$APP_DST/Contents/Helpers"
DAEMON_APP="$HELPERS/LogiOptionsDaemon.app"
rm -rf "$DAEMON_APP"
mkdir -p "$DAEMON_APP/Contents/MacOS"
cp -f "$DAEMON_BIN" "$DAEMON_APP/Contents/MacOS/LogiOptionsDaemon"
chmod +x "$DAEMON_APP/Contents/MacOS/LogiOptionsDaemon"
cp -f "$DAEMON_DIR/Info.plist" "$DAEMON_APP/Contents/Info.plist"
# Flat helper path (AppDelegate looks here first)
cp -f "$DAEMON_BIN" "$HELPERS/LogiOptionsDaemon"
chmod +x "$HELPERS/LogiOptionsDaemon"
# Fallback next to main executable
cp -f "$DAEMON_BIN" "$APP_DST/Contents/MacOS/LogiOptionsDaemon"
chmod +x "$APP_DST/Contents/MacOS/LogiOptionsDaemon"

# App icon: Flutter debug catalogs sometimes leave the stock Flutter .icns.
# Always rebuild from brand art so Dock / TCC / Finder show LogiOptions.
BRAND_ICON="$APP_DIR/assets/brand/app_icon.png"
ICONSET_DIR="$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if [[ -f "$BRAND_ICON" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "==> App icon from assets/brand/app_icon.png"
  for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" "$BRAND_ICON" --out "$ICONSET_DIR/app_icon_${size}.png" >/dev/null
  done
  TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$TMP_ICONSET"
  cp "$ICONSET_DIR/app_icon_16.png"   "$TMP_ICONSET/icon_16x16.png"
  cp "$ICONSET_DIR/app_icon_32.png"   "$TMP_ICONSET/icon_16x16@2x.png"
  cp "$ICONSET_DIR/app_icon_32.png"   "$TMP_ICONSET/icon_32x32.png"
  cp "$ICONSET_DIR/app_icon_64.png"   "$TMP_ICONSET/icon_32x32@2x.png"
  cp "$ICONSET_DIR/app_icon_128.png"  "$TMP_ICONSET/icon_128x128.png"
  cp "$ICONSET_DIR/app_icon_256.png"  "$TMP_ICONSET/icon_128x128@2x.png"
  cp "$ICONSET_DIR/app_icon_256.png"  "$TMP_ICONSET/icon_256x256.png"
  cp "$ICONSET_DIR/app_icon_512.png"  "$TMP_ICONSET/icon_256x256@2x.png"
  cp "$ICONSET_DIR/app_icon_512.png"  "$TMP_ICONSET/icon_512x512.png"
  cp "$ICONSET_DIR/app_icon_1024.png" "$TMP_ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$TMP_ICONSET" -o "$APP_DST/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$TMP_ICONSET")"
fi

# Sign with the same Developer ID as release when available so TCC
# (Accessibility, etc.) survives rebuilds. Debug keeps allow-jit entitlements
# and skips hardened-runtime for faster local iteration.
sign_debug_app() {
  local identity="$1"
  local helpers="$APP_DST/Contents/Helpers"
  local daemon_app="$helpers/LogiOptionsDaemon.app"
  local item

  echo "==> Signing with Developer ID (stable TCC identity)"
  echo "  $identity"

  # Nested helpers first (deepest → outer).
  if [[ -x "$helpers/LogiOptionsDaemon" ]]; then
    codesign --force --sign "$identity" \
      --identifier "$BUNDLE_ID_DAEMON" \
      --timestamp=none \
      "$helpers/LogiOptionsDaemon"
  fi
  if [[ -d "$daemon_app" ]]; then
    if [[ -x "$daemon_app/Contents/MacOS/LogiOptionsDaemon" ]]; then
      codesign --force --sign "$identity" \
        --identifier "$BUNDLE_ID_DAEMON" \
        --timestamp=none \
        "$daemon_app/Contents/MacOS/LogiOptionsDaemon"
    fi
    codesign --force --sign "$identity" \
      --identifier "$BUNDLE_ID_DAEMON" \
      --timestamp=none \
      "$daemon_app"
  fi
  if [[ -x "$APP_DST/Contents/MacOS/LogiOptionsDaemon" ]]; then
    codesign --force --sign "$identity" \
      --identifier "$BUNDLE_ID_DAEMON" \
      --timestamp=none \
      "$APP_DST/Contents/MacOS/LogiOptionsDaemon"
  fi

  # Flutter frameworks / dylibs (if present).
  if [[ -d "$APP_DST/Contents/Frameworks" ]]; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      codesign --force --sign "$identity" --timestamp=none "$item"
    done < <(
      find "$APP_DST/Contents/Frameworks" \
        \( -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) \
           -o -type f \( -name '*.dylib' -o -name '*.so' \) \) \
        | awk -F/ '{ print NF ":" $0 }' | sort -nr | cut -d: -f2-
    )
  fi

  local ent_args=()
  if [[ -f "$DEBUG_ENTITLEMENTS" ]]; then
    ent_args=(--entitlements "$DEBUG_ENTITLEMENTS")
  fi
  codesign --force --sign "$identity" \
    --identifier "$BUNDLE_ID_APP" \
    "${ent_args[@]}" \
    --timestamp=none \
    "$APP_DST"
  codesign --verify --deep --strict --verbose=2 "$APP_DST" 2>&1 | tail -5 || true
}

if command -v codesign >/dev/null 2>&1; then
  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    # Validate identity exists when possible
    if security find-identity -v -p codesigning 2>/dev/null \
        | grep -Fq "${DEVELOPER_ID_APPLICATION}"; then
      sign_debug_app "$DEVELOPER_ID_APPLICATION"
    else
      echo "error: DEVELOPER_ID_APPLICATION not found in keychain: $DEVELOPER_ID_APPLICATION" >&2
      security find-identity -v -p codesigning 2>/dev/null | head -20 || true
      exit 1
    fi
  else
    echo "==> No DEVELOPER_ID_APPLICATION — ad-hoc signing (TCC grants will reset each rebuild)"
    echo "    export DEVELOPER_ID_APPLICATION=\"Developer ID Application: …\" for stable permissions"
    codesign --force --sign - --identifier "$BUNDLE_ID_DAEMON" \
      "$HELPERS/LogiOptionsDaemon" 2>/dev/null || true
    codesign --force --deep --sign - --identifier "$BUNDLE_ID_DAEMON" \
      "$DAEMON_APP" 2>/dev/null || true
    if [[ -f "$DEBUG_ENTITLEMENTS" ]]; then
      codesign --force --deep --sign - --identifier "$BUNDLE_ID_APP" \
        --entitlements "$DEBUG_ENTITLEMENTS" \
        "$APP_DST" 2>/dev/null || true
    else
      codesign --force --deep --sign - --identifier "$BUNDLE_ID_APP" \
        "$APP_DST" 2>/dev/null || true
    fi
  fi
fi

echo
echo "Done."
echo "  $APP_DST"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "  signed: $DEVELOPER_ID_APPLICATION (stable TCC)"
else
  echo "  signed: ad-hoc (set DEVELOPER_ID_APPLICATION for stable Accessibility grants)"
fi
echo
echo "Run:"
echo "  open $APP_DST"
ls -la "$DIST_DIR"
