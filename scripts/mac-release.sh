#!/usr/bin/env bash
# Build, Developer-ID-sign, notarize, package DMG, and publish to GitHub Releases.
#
# Output under dist/:
#   dist/LogiOptions.app
#   dist/LogiOptions-<version>.dmg
#   GitHub Release v<version> with the DMG attached (unless --no-upload)
#
# Required:
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Name (TEAMID)"
#   gh auth login              once, for GitHub Releases
#
# Notarization keychain profile (default name: LogiOptions):
#   xcrun notarytool store-credentials LogiOptions \
#     --apple-id you@example.com --team-id TEAMID --password 'app-specific-password'
#
# Usage:
#   export DEVELOPER_ID_APPLICATION="Developer ID Application: …"
#   ./scripts/mac-release.sh
#   ./scripts/mac-release.sh 1.2.0
#   ./scripts/mac-release.sh --no-upload
#   ./scripts/mac-release.sh --no-notarize --no-upload
#   ./scripts/mac-release.sh --draft
#   ./scripts/mac-release.sh --skip-build
#
# Optional env:
#   GITHUB_REPO=owner/name     override origin remote
#   LOGIOPTIONS_NOTARY_PROFILE override notary profile name

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
DAEMON_DIR="$APP_DIR/macos/LogiOptionsDaemon"
DIST_DIR="$ROOT/dist"
PRODUCT_NAME="LogiOptions"
BUNDLE_ID_APP="com.logioptions.app"
BUNDLE_ID_DAEMON="com.logioptions.daemon"
NOTARY_PROFILE="${LOGIOPTIONS_NOTARY_PROFILE:-LogiOptions}"
ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
PUBSPEC="$APP_DIR/pubspec.yaml"
APP_DST="$DIST_DIR/${PRODUCT_NAME}.app"

BUILD_NAME=""
NO_NOTARIZE=false
NO_UPLOAD=false
NO_TAG=false
DRAFT_RELEASE=false
SKIP_BUILD=false
CLEAN=false
GITHUB_REPO="${GITHUB_REPO:-}"

declare -a CLEANUP_PATHS=()
cleanup() {
  local p
  for p in "${CLEANUP_PATHS[@]:-}"; do
    [[ -n "$p" ]] && rm -rf "$p"
  done
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: required command not found: $1" >&2; exit 1; }
}
log()  { echo "==> $*"; }
ok()   { echo "  [ok] $*"; }
warn() { echo "  [warn] $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \?//'
}

parse_pubspec_version() {
  local line
  line="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC" | head -n 1 | tr -d "\"'\r")"
  [[ -n "$line" ]] || die "failed to read version from $PUBSPEC"
  echo "${line%%+*}"
}

resolve_identity() {
  local requested="${DEVELOPER_ID_APPLICATION:-}"
  local identities
  [[ -n "$requested" ]] || die "DEVELOPER_ID_APPLICATION is not set"
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ "$requested" =~ ^[[:xdigit:]]{40}$ ]]; then
    grep -Fq "$requested" <<<"$identities" || die "identity hash not found in keychain"
  elif ! grep -Fq "$requested" <<<"$identities"; then
    die "DEVELOPER_ID_APPLICATION not found in keychain: $requested"
  fi
  echo "$requested"
}

resolve_github_repo() {
  if [[ -n "$GITHUB_REPO" ]]; then
    echo "$GITHUB_REPO"
    return
  fi
  local url
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || die "No GITHUB_REPO and no git remote origin"
  url="${url%.git}"
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return
  fi
  die "Cannot parse GitHub repo from origin; set GITHUB_REPO=owner/name"
}

generate_release_notes() {
  local prev_tag notes
  prev_tag="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -n "$prev_tag" ]]; then
    notes="$(git -C "$ROOT" log "${prev_tag}..HEAD" --pretty=format:'- %s' --no-merges 2>/dev/null \
      | grep -v '^- Bump version' | grep -v '^- Merge ' | head -30 || true)"
  else
    notes="$(git -C "$ROOT" log --pretty=format:'- %s' --no-merges -20 2>/dev/null \
      | grep -v '^- Bump version' | grep -v '^- Merge ' || true)"
  fi
  if [[ -z "${notes//[[:space:]]/}" ]]; then
    notes='- Bug fixes and improvements'
  fi
  printf '%s\n' "$notes"
}

sign_app_bundle() {
  local app_path="$1"
  local identity="$2"
  local frameworks_dir="$app_path/Contents/Frameworks"
  local helpers_dir="$app_path/Contents/Helpers"
  local signable

  log "Signing nested code"
  if [[ -d "$helpers_dir" ]]; then
    while IFS= read -r signable; do
      [[ -n "$signable" ]] || continue
      echo "  sign $(basename "$signable")"
      codesign --force --sign "$identity" \
        --identifier "$BUNDLE_ID_DAEMON" \
        --options runtime --timestamp \
        "$signable"
    done < <(
      find "$helpers_dir" \
        \( -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \) \
           -o -type f \( -perm -111 -o -name '*.dylib' \) \) \
        | awk -F/ '{ print NF ":" $0 }' | sort -nr | cut -d: -f2-
    )
  fi
  if [[ -d "$frameworks_dir" ]]; then
    while IFS= read -r signable; do
      [[ -n "$signable" ]] || continue
      echo "  sign $(basename "$signable")"
      codesign --force --sign "$identity" \
        --options runtime --timestamp \
        "$signable"
    done < <(
      find "$frameworks_dir" \
        \( -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) \
           -o -type f \( -name '*.dylib' -o -name '*.so' \) \) \
        | awk -F/ '{ print NF ":" $0 }' | sort -nr | cut -d: -f2-
    )
  fi
  if [[ -x "$app_path/Contents/MacOS/LogiOptionsDaemon" ]]; then
    codesign --force --sign "$identity" \
      --identifier "$BUNDLE_ID_DAEMON" \
      --options runtime --timestamp \
      "$app_path/Contents/MacOS/LogiOptionsDaemon"
  fi
  echo "  sign $(basename "$app_path")"
  codesign --force --sign "$identity" \
    --identifier "$BUNDLE_ID_APP" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime --timestamp \
    "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
  ok "Signed $app_path"
}

sign_dmg() {
  local dmg_path="$1"
  local identity="$2"
  log "Signing DMG"
  codesign --force --timestamp --sign "$identity" "$dmg_path"
  codesign --verify --strict --verbose=2 "$dmg_path"
  ok "Signed DMG"
}

create_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/logioptions-dmg.XXXXXX")"
  CLEANUP_PATHS+=("$staging")
  ditto "$app_path" "$staging/${PRODUCT_NAME}.app"
  ln -s /Applications "$staging/Applications"
  rm -f "$dmg_path"
  if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --volumeName "$PRODUCT_NAME" --format UDZO "$staging" "$dmg_path"
  else
    hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg_path"
  fi
  ok "Created $dmg_path"
}

notarize_and_staple() {
  local app_path="$1"
  local dmg_path="$2"
  local submit_output submission_id

  log "Notarizing with profile: $NOTARY_PROFILE"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "No notarytool profile '$NOTARY_PROFILE'. Run store-credentials or use --no-notarize"
  fi

  if ! submit_output=$(xcrun notarytool submit "$dmg_path" \
      --keychain-profile "$NOTARY_PROFILE" --wait --output-format json 2>&1); then
    echo "$submit_output" >&2
    die "Notarization submission failed"
  fi
  if ! echo "$submit_output" | grep -q '"status"[[:space:]]*:[[:space:]]*"Accepted"'; then
    echo "$submit_output" >&2
    submission_id=$(echo "$submit_output" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    if [[ -n "$submission_id" ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    die "Notarization was not accepted"
  fi
  ok "Notarization accepted"
  xcrun stapler staple "$app_path"
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$app_path"
  xcrun stapler validate "$dmg_path"
  ok "Stapled app and DMG"
  spctl --assess --type exec --verbose=4 "$app_path"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"
  ok "Gatekeeper accepted app and DMG"
}

embed_daemon_and_icon() {
  local app_path="$1"
  local daemon_bin="$2"
  local helpers daemon_app brand_icon iconset_dir tmp_iconset size

  helpers="$app_path/Contents/Helpers"
  daemon_app="$helpers/LogiOptionsDaemon.app"
  mkdir -p "$helpers"
  rm -rf "$daemon_app"
  mkdir -p "$daemon_app/Contents/MacOS"
  cp -f "$daemon_bin" "$daemon_app/Contents/MacOS/LogiOptionsDaemon"
  chmod +x "$daemon_app/Contents/MacOS/LogiOptionsDaemon"
  cp -f "$DAEMON_DIR/Info.plist" "$daemon_app/Contents/Info.plist"
  cp -f "$daemon_bin" "$helpers/LogiOptionsDaemon"
  chmod +x "$helpers/LogiOptionsDaemon"
  cp -f "$daemon_bin" "$app_path/Contents/MacOS/LogiOptionsDaemon"
  chmod +x "$app_path/Contents/MacOS/LogiOptionsDaemon"

  brand_icon="$APP_DIR/assets/brand/app_icon.png"
  iconset_dir="$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
  if [[ -f "$brand_icon" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    log "App icon from brand art"
    for size in 16 32 64 128 256 512 1024; do
      sips -z "$size" "$size" "$brand_icon" --out "$iconset_dir/app_icon_${size}.png" >/dev/null
    done
    tmp_iconset="$(mktemp -d)/AppIcon.iconset"
    CLEANUP_PATHS+=("$(dirname "$tmp_iconset")")
    mkdir -p "$tmp_iconset"
    cp "$iconset_dir/app_icon_16.png"   "$tmp_iconset/icon_16x16.png"
    cp "$iconset_dir/app_icon_32.png"   "$tmp_iconset/icon_16x16@2x.png"
    cp "$iconset_dir/app_icon_32.png"   "$tmp_iconset/icon_32x32.png"
    cp "$iconset_dir/app_icon_64.png"   "$tmp_iconset/icon_32x32@2x.png"
    cp "$iconset_dir/app_icon_128.png"  "$tmp_iconset/icon_128x128.png"
    cp "$iconset_dir/app_icon_256.png"  "$tmp_iconset/icon_128x128@2x.png"
    cp "$iconset_dir/app_icon_256.png"  "$tmp_iconset/icon_256x256.png"
    cp "$iconset_dir/app_icon_512.png"  "$tmp_iconset/icon_256x256@2x.png"
    cp "$iconset_dir/app_icon_512.png"  "$tmp_iconset/icon_512x512.png"
    cp "$iconset_dir/app_icon_1024.png" "$tmp_iconset/icon_512x512@2x.png"
    iconutil -c icns "$tmp_iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
  fi
}

publish_github_release() {
  local version="$1"
  local dmg_path="$2"
  local tag_name="v${version}"
  local repo head_commit notes body_file

  need gh
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

  repo="$(resolve_github_repo)"
  head_commit="$(git -C "$ROOT" rev-parse HEAD)"
  notes="$(generate_release_notes)"

  log "Publishing GitHub release $tag_name to $repo"

  if gh release view "$tag_name" --repo "$repo" >/dev/null 2>&1; then
    die "GitHub release already exists for $tag_name on $repo"
  fi

  if [[ "$NO_TAG" == "false" ]]; then
    if git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$tag_name" >/dev/null; then
      local existing
      existing="$(git -C "$ROOT" rev-parse "refs/tags/$tag_name^{}")"
      if [[ "$existing" != "$head_commit" ]]; then
        die "Local tag $tag_name does not point at HEAD"
      fi
      ok "Local tag $tag_name already at HEAD"
    else
      git -C "$ROOT" tag -a "$tag_name" -m "Release $PRODUCT_NAME $version"
      ok "Created tag $tag_name"
    fi
    if git -C "$ROOT" ls-remote --tags origin "refs/tags/$tag_name" 2>/dev/null | grep -q .; then
      ok "Remote tag $tag_name already exists"
    else
      git -C "$ROOT" push origin "refs/tags/$tag_name:refs/tags/$tag_name"
      ok "Pushed tag $tag_name"
    fi
  fi

  body_file="$(mktemp "${TMPDIR:-/tmp}/logioptions-notes.XXXXXX.md")"
  CLEANUP_PATHS+=("$body_file")
  cat >"$body_file" <<EOF
## What's New

$notes

## Downloads

- \`$(basename "$dmg_path")\` — signed and notarized macOS disk image

## Install

1. Open the DMG and drag **${PRODUCT_NAME}** to Applications.
2. Grant **Accessibility** to ${PRODUCT_NAME} and LogiOptionsDaemon if prompted.
3. Stop official Logi Options+ before use (\`tools/stop_options_plus.sh\`).

## System requirements

- macOS 13+ on Apple Silicon or Intel
EOF

  local -a gh_args=(
    release create "$tag_name"
    --repo "$repo"
    --title "${PRODUCT_NAME} ${version}"
    --notes-file "$body_file"
  )
  if [[ "$DRAFT_RELEASE" == "true" ]]; then
    gh_args+=(--draft)
  fi
  if [[ "$NO_TAG" == "false" ]]; then
    gh_args+=(--verify-tag)
  else
    gh_args+=(--target "$head_commit")
  fi
  gh_args+=("$dmg_path")

  gh "${gh_args[@]}"
  ok "GitHub release https://github.com/${repo}/releases/tag/${tag_name}"
}

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --no-notarize) NO_NOTARIZE=true; shift ;;
    --no-upload) NO_UPLOAD=true; shift ;;
    --no-tag) NO_TAG=true; shift ;;
    --draft) DRAFT_RELEASE=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --clean) CLEAN=true; shift ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "$BUILD_NAME" ]] || die "Only one VERSION argument is supported"
      BUILD_NAME="$1"
      shift
      ;;
  esac
done

need flutter
need swift
need rsync
need codesign
need security
need ditto
need xcrun
need spctl
need git
if [[ "$NO_UPLOAD" == "false" ]]; then
  need gh
fi

[[ -f "$ENTITLEMENTS" ]] || die "Missing entitlements: $ENTITLEMENTS"

if [[ -z "$BUILD_NAME" ]]; then
  BUILD_NAME="$(parse_pubspec_version)"
fi
if ! [[ "$BUILD_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  die "Invalid VERSION format: $BUILD_NAME"
fi

DMG_PATH="$DIST_DIR/${PRODUCT_NAME}-${BUILD_NAME}.dmg"
IDENTITY="$(resolve_identity)"

log "Release $PRODUCT_NAME $BUILD_NAME"
echo "  identity: $IDENTITY"
echo "  notary:   $NOTARY_PROFILE"
echo "  app:      $APP_DST"
echo "  dmg:      $DMG_PATH"
if [[ "$NO_UPLOAD" == "false" ]]; then
  echo "  github:   $(resolve_github_repo)  tag=v${BUILD_NAME}"
else
  echo "  github:   skipped"
fi

# --- build ---
if [[ "$SKIP_BUILD" == "false" ]]; then
  if [[ "$CLEAN" == "true" ]]; then
    log "flutter clean"
    (cd "$APP_DIR" && flutter clean)
  fi

  log "Building LogiOptionsDaemon release"
  (cd "$DAEMON_DIR" && swift build -c release)
  DAEMON_BIN="$(cd "$DAEMON_DIR" && swift build -c release --show-bin-path)/LogiOptionsDaemon"
  [[ -x "$DAEMON_BIN" ]] || die "daemon binary missing at $DAEMON_BIN"

  log "Building Flutter macOS release"
  (cd "$APP_DIR" && flutter pub get && flutter build macos --release --build-name "$BUILD_NAME")

  APP_SRC=""
  for c in \
    "$APP_DIR/build/macos/Build/Products/Release/${PRODUCT_NAME}.app" \
    "$APP_DIR/build/macos/Build/Products/Release/LogiOptions.app"
  do
    if [[ -d "$c" ]]; then APP_SRC="$c"; break; fi
  done
  if [[ -z "$APP_SRC" ]]; then
    APP_SRC="$(find "$APP_DIR/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1 || true)"
  fi
  [[ -d "$APP_SRC" ]] || die "could not find Release .app"

  log "Assembling $APP_DST"
  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR"
  rsync -a --delete "$APP_SRC/" "$APP_DST/"
  rm -f "$DIST_DIR/.DS_Store" 2>/dev/null || true
  embed_daemon_and_icon "$APP_DST" "$DAEMON_BIN"
else
  [[ -d "$APP_DST" ]] || die "--skip-build requires existing $APP_DST"
  log "Skipping build; re-signing existing app"
fi

sign_app_bundle "$APP_DST" "$IDENTITY"

log "Creating DMG"
create_dmg "$APP_DST" "$DMG_PATH"
sign_dmg "$DMG_PATH" "$IDENTITY"

if [[ "$NO_NOTARIZE" == "true" ]]; then
  warn "Notarization skipped"
else
  notarize_and_staple "$APP_DST" "$DMG_PATH"
fi

if [[ "$NO_UPLOAD" == "true" ]]; then
  warn "GitHub upload skipped"
else
  publish_github_release "$BUILD_NAME" "$DMG_PATH"
fi

log "Done"
echo "  App: $APP_DST"
echo "  DMG: $DMG_PATH"
if [[ "$NO_UPLOAD" == "false" ]]; then
  echo "  Release: https://github.com/$(resolve_github_repo)/releases/tag/v${BUILD_NAME}"
fi
ls -la "$DIST_DIR"
