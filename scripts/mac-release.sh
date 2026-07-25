#!/usr/bin/env bash
# Build release .app, Developer-ID-sign, notarize, package DMG under dist/,
# and publish to GitHub Releases.
#
# Pattern: MonkeyT3ch/aSnap scripts/build-release.sh + mPDF scripts/signing.sh
# Never ad-hoc. Requires Developer ID Application.
#
# Output:
#   dist/LogiOptions.app
#   dist/LogiOptions-<version>.dmg
#   GitHub Release v<version> with the DMG attached (unless --no-upload)
#
# Required:
#   DEVELOPER_ID_APPLICATION   (or exactly one Developer ID cert in keychain)
#   gh auth login              for GitHub Releases
#   notarytool profile LogiOptions (or LOGIOPTIONS_NOTARY_PROFILE)
#
# Usage:
#   ./scripts/mac-release.sh
#   ./scripts/mac-release.sh 0.1.1
#   ./scripts/mac-release.sh 0.1.1 --no-upload
#   ./scripts/mac-release.sh --no-notarize --no-upload
#   ./scripts/mac-release.sh --skip-build
#   ./scripts/mac-release.sh --draft
#
# Optional env:
#   GITHUB_REPO=owner/name
#   LOGIOPTIONS_NOTARY_PROFILE  (default: LogiOptions)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=signing.sh
source "$ROOT/scripts/signing.sh"

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
GITHUB_REPO_DEFAULT=""

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
log()  { echo ""; echo "==> $*"; }
ok()   { echo "  [ok] $*"; }
warn() { echo "  [warn] $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \?//'
}

parse_pubspec_version() {
  local line
  line="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC" | head -n 1 | tr -d "\"'\r")"
  [[ -n "$line" ]] || die "failed to read version from $PUBSPEC"
  echo "${line%%+*}"
}

parse_pubspec_build_number() {
  local line n
  line="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC" | head -n 1 | tr -d "\"'\r")"
  n="${line##*+}"
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "$n"
  else
    date +%Y%m%d%H%M
  fi
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
  local version_arg="${1:-}"
  local current_tag="" prev_tag notes
  [[ -n "$version_arg" ]] && current_tag="v${version_arg}"

  prev_tag="$(
    git -C "$ROOT" tag -l 'v*' --sort=-v:refname \
      | while read -r t; do
          [[ -n "$current_tag" && "$t" == "$current_tag" ]] && continue
          echo "$t"
          break
        done
  )"
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

create_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/logioptions-dmg.XXXXXX")"
  CLEANUP_PATHS+=("$staging")
  ditto "$app_path" "$staging/${PRODUCT_NAME}.app"
  ln -s /Applications "$staging/Applications"
  rm -f "$dmg_path"
  # Prefer hdiutil (aSnap); diskutil image create on newer macOS.
  if hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg_path" >/dev/null; then
    ok "Created $dmg_path"
  elif diskutil image create from --volumeName "$PRODUCT_NAME" --format UDZO "$staging" "$dmg_path" 2>/dev/null; then
    ok "Created $dmg_path (diskutil)"
  else
    die "Failed to create DMG at $dmg_path"
  fi
  [[ -f "$dmg_path" && -s "$dmg_path" ]] || die "DMG missing or empty: $dmg_path"
}

wait_for_remote_tag() {
  local repo="$1"
  local tag_name="$2"
  local i
  for i in $(seq 1 15); do
    if gh api "repos/${repo}/git/ref/tags/${tag_name}" >/dev/null 2>&1; then
      return 0
    fi
    if git -C "$ROOT" ls-remote --tags origin "refs/tags/${tag_name}" 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
  done
  return 1
}

publish_github_release() {
  local version="$1"
  local dmg_path="$2"
  local tag_name="v${version}"
  local repo head_commit notes body_file

  need gh
  [[ -f "$dmg_path" ]] || die "DMG missing for upload: $dmg_path"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

  repo="$(resolve_github_repo)"
  head_commit="$(git -C "$ROOT" rev-parse HEAD)"
  notes="$(generate_release_notes "$version")"

  log "Publishing GitHub release $tag_name → $repo (${head_commit:0:8})"

  if [[ "$NO_TAG" == "false" ]]; then
    if git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$tag_name" >/dev/null; then
      local existing
      existing="$(git -C "$ROOT" rev-parse "refs/tags/$tag_name^{}")"
      if [[ "$existing" != "$head_commit" ]]; then
        die "Local tag $tag_name points at ${existing:0:8}, not HEAD ${head_commit:0:8}"
      fi
      ok "Local tag $tag_name at HEAD"
    else
      git -C "$ROOT" tag -a "$tag_name" -m "Release $PRODUCT_NAME $version"
      ok "Created tag $tag_name"
    fi
    if git -C "$ROOT" ls-remote --tags origin "refs/tags/$tag_name" 2>/dev/null | grep -q .; then
      ok "Remote tag $tag_name already on origin"
    else
      git -C "$ROOT" push origin "refs/tags/$tag_name:refs/tags/$tag_name"
      ok "Pushed tag $tag_name"
    fi
    wait_for_remote_tag "$repo" "$tag_name" \
      || die "Tag $tag_name not visible on GitHub; push failed?"
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

  if gh release view "$tag_name" --repo "$repo" >/dev/null 2>&1; then
    log "Release $tag_name exists — uploading DMG (clobber)"
    gh release upload "$tag_name" "$dmg_path" --repo "$repo" --clobber
    gh release edit "$tag_name" --repo "$repo" \
      --notes-file "$body_file" \
      --title "${PRODUCT_NAME} ${version}" || true
    [[ "$DRAFT_RELEASE" == "false" ]] \
      && gh release edit "$tag_name" --repo "$repo" --draft=false 2>/dev/null || true
    ok "Updated https://github.com/${repo}/releases/tag/${tag_name}"
  else
    local -a gh_args=(
      release create "$tag_name"
      --repo "$repo"
      --title "${PRODUCT_NAME} ${version}"
      --notes-file "$body_file"
      --target "$head_commit"
    )
    [[ "$DRAFT_RELEASE" == "true" ]] && gh_args+=(--draft)
    gh_args+=("$dmg_path")
    log "gh release create $tag_name"
    gh "${gh_args[@]}"
    ok "Created https://github.com/${repo}/releases/tag/${tag_name}"
  fi

  gh release view "$tag_name" --repo "$repo" >/dev/null \
    || die "Release $tag_name not found after publish"
  gh release view "$tag_name" --repo "$repo" --json assets --jq '.assets[].name' \
    | grep -Fxq "$(basename "$dmg_path")" \
    || die "DMG $(basename "$dmg_path") missing from release assets"
  ok "GitHub release verified with DMG asset"
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
    -*) die "Unknown option: $1" ;;
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
need hdiutil
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
IDENTITY="$(resolve_developer_id)"

log "Release $PRODUCT_NAME $BUILD_NAME"
echo "  identity: $IDENTITY"
echo "  notary:   $NOTARY_PROFILE"
echo "  app:      $APP_DST"
echo "  dmg:      $DMG_PATH"
if [[ "$NO_UPLOAD" == "false" ]]; then
  echo "  github:   $(resolve_github_repo)  tag=v${BUILD_NAME}"
else
  echo "  github:   skipped (--no-upload)"
fi

# --- 1. Build release .app ---
if [[ "$SKIP_BUILD" == "false" ]]; then
  if [[ "$CLEAN" == "true" ]]; then
    log "flutter clean"
    (cd "$APP_DIR" && flutter clean)
  fi

  log "1/5 Building LogiOptionsDaemon (release)"
  (cd "$DAEMON_DIR" && swift build -c release)
  DAEMON_BIN="$(cd "$DAEMON_DIR" && swift build -c release --show-bin-path)/LogiOptionsDaemon"
  [[ -x "$DAEMON_BIN" ]] || die "daemon binary missing at $DAEMON_BIN"

  BUILD_NUMBER="$(parse_pubspec_build_number)"
  log "1/5 Building Flutter macOS release (name=$BUILD_NAME number=$BUILD_NUMBER)"
  (cd "$APP_DIR" && flutter pub get && \
    flutter build macos --release \
      --build-name "$BUILD_NAME" \
      --build-number "$BUILD_NUMBER")

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
  mkdir -p "$DIST_DIR"
  rm -rf "$APP_DST"
  rsync -a "$APP_SRC/" "$APP_DST/"
  rm -f "$DIST_DIR/.DS_Store" 2>/dev/null || true
  embed_daemon_and_icon "$APP_DST" "$DAEMON_BIN"
  ok "Release .app assembled"
else
  [[ -d "$APP_DST" ]] || die "--skip-build requires existing $APP_DST"
  log "1/5 Skipping build; using existing $APP_DST"
fi

# --- 2. Sign (Developer ID, never ad-hoc) ---
log "2/5 Sign .app (Developer ID + hardened runtime)"
sign_macos_app_bundle \
  "$APP_DST" \
  "$IDENTITY" \
  "$ENTITLEMENTS" \
  1 \
  "$BUNDLE_ID_APP" \
  "$BUNDLE_ID_DAEMON"

# --- 3. DMG ---
log "3/5 Create + sign DMG → $DMG_PATH"
create_dmg "$APP_DST" "$DMG_PATH"
sign_disk_image "$DMG_PATH" "$IDENTITY"
ok "DMG $(du -h "$DMG_PATH" | awk '{print $1}')"

# --- 4. Notarize ---
if [[ "$NO_NOTARIZE" == "true" ]]; then
  warn "4/5 Notarization skipped"
else
  log "4/5 Notarize + staple"
  if ! notary_profile_ok "$NOTARY_PROFILE"; then
    die "Notary profile '$NOTARY_PROFILE' missing (unlike aSnap we do not silently skip).

  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --apple-id … --team-id … --password …
  Or pass --no-notarize for a signed-only local DMG."
  fi
  notarize_and_staple "$DMG_PATH" "$APP_DST" "$NOTARY_PROFILE"
  verify_gatekeeper "$APP_DST" app
  verify_gatekeeper "$DMG_PATH" dmg
fi

# --- 5. GitHub Releases ---
if [[ "$NO_UPLOAD" == "true" ]]; then
  warn "5/5 GitHub upload skipped"
else
  log "5/5 Publish GitHub Release v${BUILD_NAME}"
  publish_github_release "$BUILD_NAME" "$DMG_PATH"
fi

log "Done — release artifacts"
echo "  App:     $APP_DST"
echo "  DMG:     $DMG_PATH"
refuse_adhoc_signature "$APP_DST"
if [[ "$NO_UPLOAD" == "false" ]]; then
  REPO="$(resolve_github_repo)"
  echo "  Release: https://github.com/${REPO}/releases/tag/v${BUILD_NAME}"
  echo "  Asset:   https://github.com/${REPO}/releases/download/v${BUILD_NAME}/$(basename "$DMG_PATH")"
fi
ls -la "$DIST_DIR"
