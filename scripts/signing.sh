#!/usr/bin/env bash
# Shared Developer ID signing / notarization helpers for LogiOptions.
# Pattern follows MonkeyT3ch/mPDF scripts/signing.sh and aSnap build-release.sh.
#
# Never ad-hoc. Release and debug both require Developer ID Application.

: "${LOGIOPTIONS_PRODUCT_NAME:=LogiOptions}"
: "${LOGIOPTIONS_BUNDLE_ID_APP:=com.logioptions.app}"
: "${LOGIOPTIONS_BUNDLE_ID_DAEMON:=com.logioptions.daemon}"
: "${LOGIOPTIONS_NOTARY_PROFILE:=LogiOptions}"

_sign_log()  { echo "  $*" >&2; }
_sign_ok()   { echo "  [ok] $*" >&2; }
_sign_warn() { echo "  [warn] $*" >&2; }
_sign_die()  { echo "error: $*" >&2; exit 1; }

# codesign with retries. Apple's timestamp service (timestamp.apple.com) flakes
# regularly; a single blip would otherwise abort the whole release under set -e.
: "${LOGIOPTIONS_CODESIGN_RETRIES:=5}"
_codesign() {
  local attempt=1 output rc
  while :; do
    if output="$(codesign "$@" 2>&1)"; then
      [[ -n "$output" ]] && echo "$output" >&2
      return 0
    fi
    rc=$?
    if (( attempt >= LOGIOPTIONS_CODESIGN_RETRIES )); then
      echo "$output" >&2
      return "$rc"
    fi
    if ! grep -Eqi 'timestamp (service|server).*(not available|unavailable)|The timestamp service is not available|timestamp.*(timed out|network)' <<<"$output"; then
      echo "$output" >&2
      return "$rc"
    fi
    _sign_warn "timestamp service unavailable (attempt $attempt/$LOGIOPTIONS_CODESIGN_RETRIES); retrying in $(( attempt * 5 ))s"
    sleep $(( attempt * 5 ))
    (( attempt++ ))
  done
}

# Resolve Developer ID Application. Env DEVELOPER_ID_APPLICATION or sole cert.
resolve_developer_id() {
  local requested="${DEVELOPER_ID_APPLICATION:-}"
  local identities matches=()

  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  if [[ -n "$requested" ]]; then
    if [[ "$requested" =~ ^[[:xdigit:]]{40}$ ]]; then
      grep -Fq "$requested" <<<"$identities" \
        || _sign_die "identity hash not found in keychain: $requested"
    elif ! grep -Fq "$requested" <<<"$identities"; then
      _sign_die "DEVELOPER_ID_APPLICATION not found in keychain: $requested

Available identities:
$identities"
    fi
    printf '%s\n' "$requested"
    return 0
  fi

  while IFS= read -r match; do
    [[ -n "$match" ]] && matches+=("$match")
  done < <(echo "$identities" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')

  if [[ ${#matches[@]} -eq 0 ]]; then
    _sign_die "No Developer ID Application certificate in keychain.

Install a Developer ID Application cert, or set:
  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Name (TEAMID)\""
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    _sign_die "Multiple Developer ID Application identities; set DEVELOPER_ID_APPLICATION to one of:
$(printf '  %s\n' "${matches[@]}")"
  fi
  _sign_warn "DEVELOPER_ID_APPLICATION unset; using sole keychain identity:"
  _sign_warn "  ${matches[0]}"
  printf '%s\n' "${matches[0]}"
}

# Fail hard if the bundle is ad-hoc signed.
refuse_adhoc_signature() {
  local path="$1"
  local info
  info="$(codesign -dv --verbose=4 "$path" 2>&1 || true)"
  if echo "$info" | grep -Eq 'Signature=adhoc|flags=0x2\(adhoc\)'; then
    _sign_die "$path is ad-hoc signed — Developer ID is required (never use codesign -s -)"
  fi
}

# Sign nested frameworks / helpers deepest-first, then the outer .app.
# hardened=1 → --options runtime --timestamp (release / notarization).
# hardened=0 → --timestamp=none (local debug rebuilds, still Developer ID).
sign_macos_app_bundle() {
  local app_path="$1"
  local identity="$2"
  local entitlements_path="${3:-}"
  local hardened="${4:-1}"
  local bundle_id_app="${5:-$LOGIOPTIONS_BUNDLE_ID_APP}"
  local bundle_id_daemon="${6:-$LOGIOPTIONS_BUNDLE_ID_DAEMON}"

  local codesign_flags=(--force --sign "$identity")
  if [[ "$hardened" == "1" ]]; then
    codesign_flags+=(--options runtime --timestamp)
    _sign_log "Signing $app_path (Developer ID, hardened runtime)"
  else
    codesign_flags+=(--timestamp=none)
    _sign_log "Signing $app_path (Developer ID, debug entitlements)"
  fi

  local helpers="$app_path/Contents/Helpers"
  local frameworks="$app_path/Contents/Frameworks"
  local item

  # Nested helpers / daemon mini-bundle (deepest first).
  if [[ -d "$helpers" ]]; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      _sign_log "sign $(basename "$item")"
      _codesign "${codesign_flags[@]}" --identifier "$bundle_id_daemon" "$item"
    done < <(
      find "$helpers" \
        \( -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \) \
           -o -type f \( -perm -111 -o -name '*.dylib' \) \) \
        | awk -F/ '{ print NF ":" $0 }' | sort -nr | cut -d: -f2-
    )
  fi

  if [[ -d "$frameworks" ]]; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      _sign_log "sign $(basename "$item")"
      _codesign "${codesign_flags[@]}" "$item"
    done < <(
      find "$frameworks" \
        \( -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) \
           -o -type f \( -name '*.dylib' -o -name '*.so' \) \) \
        | awk -F/ '{ print NF ":" $0 }' | sort -nr | cut -d: -f2-
    )
  fi

  if [[ -x "$app_path/Contents/MacOS/LogiOptionsDaemon" ]]; then
    _codesign "${codesign_flags[@]}" --identifier "$bundle_id_daemon" \
      "$app_path/Contents/MacOS/LogiOptionsDaemon"
  fi

  local ent_args=()
  if [[ -n "$entitlements_path" && -f "$entitlements_path" ]]; then
    ent_args=(--entitlements "$entitlements_path")
  fi
  _codesign "${codesign_flags[@]}" --identifier "$bundle_id_app" \
    "${ent_args[@]}" \
    "$app_path"

  codesign --verify --deep --strict --verbose=2 "$app_path" >&2
  refuse_adhoc_signature "$app_path"
  _sign_ok "Signed $app_path"
}

sign_disk_image() {
  local dmg_path="$1"
  local identity="$2"
  _sign_log "Signing DMG $dmg_path"
  _codesign --force --timestamp --sign "$identity" "$dmg_path"
  codesign --verify --strict --verbose=2 "$dmg_path" >&2
  refuse_adhoc_signature "$dmg_path"
  _sign_ok "Signed DMG"
}

notary_profile_ok() {
  local profile="${1:-$LOGIOPTIONS_NOTARY_PROFILE}"
  xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1
}

# Notarize a DMG (or zip). Staple both DMG and optional companion .app.
notarize_and_staple() {
  local dmg_path="$1"
  local app_path="${2:-}"
  local profile="${3:-$LOGIOPTIONS_NOTARY_PROFILE}"
  local submit_output submission_id

  notary_profile_ok "$profile" || _sign_die "No notarytool profile '$profile'.

Create once:
  xcrun notarytool store-credentials $profile \\
    --apple-id you@example.com --team-id TEAMID --password 'app-specific-password'"

  _sign_log "Notarizing $dmg_path (profile=$profile)"
  if ! submit_output=$(xcrun notarytool submit "$dmg_path" \
      --keychain-profile "$profile" --wait --output-format json 2>&1); then
    echo "$submit_output" >&2
    _sign_die "Notarization submission failed"
  fi
  if ! echo "$submit_output" | grep -q '"status"[[:space:]]*:[[:space:]]*"Accepted"'; then
    echo "$submit_output" >&2
    submission_id=$(echo "$submit_output" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    if [[ -n "$submission_id" ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$profile" >&2 || true
    fi
    _sign_die "Notarization was not Accepted"
  fi
  _sign_ok "Notarization Accepted"

  if [[ -n "$app_path" && -d "$app_path" ]]; then
    xcrun stapler staple "$app_path" >&2
    xcrun stapler validate "$app_path" >&2
  fi
  xcrun stapler staple "$dmg_path" >&2
  xcrun stapler validate "$dmg_path" >&2
  _sign_ok "Stapled artifacts"
}

# Gatekeeper check — warn-only for CI flakiness after Accepted notarization.
verify_gatekeeper() {
  local path="$1"
  local kind="${2:-app}" # app | dmg
  local args=(--assess --verbose=4)

  if [[ "$kind" == "dmg" ]]; then
    args+=(--type open --context context:primary-signature)
  else
    args+=(--type exec)
  fi

  if spctl "${args[@]}" "$path" 2>&1; then
    _sign_ok "Gatekeeper accepted $path"
    return 0
  fi
  _sign_warn "spctl rejected $path (non-fatal if notarization Accepted)"
  return 0
}
