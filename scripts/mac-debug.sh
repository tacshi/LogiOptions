#!/usr/bin/env bash
# Build a Developer-ID-signed debug app into dist/LogiOptions.app
#
# Same identity as release so Accessibility / Automation TCC survives rebuilds.
# Never ad-hoc (matches mPDF/aSnap policy).
#
# Required:
#   DEVELOPER_ID_APPLICATION  (or exactly one Developer ID cert in keychain)
#
# Usage (repo root):
#   ./scripts/mac-debug.sh
#   open dist/LogiOptions.app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=signing.sh
source "$ROOT/scripts/signing.sh"

APP_DIR="$ROOT/app"
DAEMON_DIR="$APP_DIR/macos/LogiOptionsDaemon"
DIST_DIR="$ROOT/dist"
PRODUCT_NAME="LogiOptions"
APP_DST="$DIST_DIR/${PRODUCT_NAME}.app"
DEBUG_ENTITLEMENTS="$APP_DIR/macos/Runner/DebugProfile.entitlements"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: required command not found: $1" >&2; exit 1; }
}

need flutter
need swift
need rsync
need codesign
need security

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

IDENTITY="$(resolve_developer_id)"

: >> /tmp/logioptions.daemon.out.log
: >> /tmp/logioptions.daemon.err.log

echo "==> Building LogiOptionsDaemon (debug)"
(
  cd "$DAEMON_DIR"
  swift build -c debug
)
DAEMON_BIN="$(cd "$DAEMON_DIR" && swift build -c debug --show-bin-path)/LogiOptionsDaemon"
[[ -x "$DAEMON_BIN" ]] || { echo "error: daemon binary missing at $DAEMON_BIN" >&2; exit 1; }

echo "==> Building Flutter macOS app (debug)"
(
  cd "$APP_DIR"
  flutter pub get
  flutter build macos --debug
)

APP_SRC=""
for c in \
  "$APP_DIR/build/macos/Build/Products/Debug/${PRODUCT_NAME}.app" \
  "$APP_DIR/build/macos/Build/Products/Debug/LogiOptions.app"
do
  if [[ -d "$c" ]]; then APP_SRC="$c"; break; fi
done
if [[ -z "$APP_SRC" ]]; then
  APP_SRC="$(find "$APP_DIR/build/macos/Build/Products/Debug" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1 || true)"
fi
[[ -d "$APP_SRC" ]] || { echo "error: could not find Debug .app" >&2; exit 1; }

echo "==> Assembling $APP_DST"
mkdir -p "$DIST_DIR"
rm -rf "$APP_DST"
rsync -a "$APP_SRC/" "$APP_DST/"
rm -f "$DIST_DIR/.DS_Store" 2>/dev/null || true

HELPERS="$APP_DST/Contents/Helpers"
DAEMON_APP="$HELPERS/LogiOptionsDaemon.app"
rm -rf "$DAEMON_APP"
mkdir -p "$DAEMON_APP/Contents/MacOS"
cp -f "$DAEMON_BIN" "$DAEMON_APP/Contents/MacOS/LogiOptionsDaemon"
chmod +x "$DAEMON_APP/Contents/MacOS/LogiOptionsDaemon"
cp -f "$DAEMON_DIR/Info.plist" "$DAEMON_APP/Contents/Info.plist"
cp -f "$DAEMON_BIN" "$HELPERS/LogiOptionsDaemon"
chmod +x "$HELPERS/LogiOptionsDaemon"
cp -f "$DAEMON_BIN" "$APP_DST/Contents/MacOS/LogiOptionsDaemon"
chmod +x "$APP_DST/Contents/MacOS/LogiOptionsDaemon"

BRAND_ICON="$APP_DIR/assets/brand/app_icon.png"
ICONSET_DIR="$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if [[ -f "$BRAND_ICON" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "==> App icon from brand art"
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

# Developer ID only — never ad-hoc. Debug entitlements, no hardened runtime
# (same idea as mPDF debug: identity stable for TCC, faster local iteration).
sign_macos_app_bundle \
  "$APP_DST" \
  "$IDENTITY" \
  "$DEBUG_ENTITLEMENTS" \
  0

echo
echo "Done."
echo "  $APP_DST"
echo "  signed: $IDENTITY (Developer ID — never ad-hoc)"
echo
echo "Run:"
echo "  open $APP_DST"
ls -la "$DIST_DIR"
