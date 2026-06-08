#!/usr/bin/env bash

# Source this script before swift, xcodebuild, or fastlane commands so every CI
# step uses a Swift 6 capable Xcode.

_pocketcasts_swift_major() {
  local developer_dir="${1:-}"
  local output

  if [[ -n "$developer_dir" ]]; then
    output="$(DEVELOPER_DIR="$developer_dir" xcrun swift --version 2>/dev/null || true)"
  else
    output="$(xcrun swift --version 2>/dev/null || swift --version 2>/dev/null || true)"
  fi

  echo "$output" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1
}

_pocketcasts_add_xcode_candidate() {
  local app_path="$1"

  [[ -d "$app_path/Contents/Developer" ]] || return 0
  _pocketcasts_xcode_candidates+=("$app_path")
}

_pocketcasts_find_compatible_xcode() {
  local requested_version="$1"
  local requested_major_minor=""
  local app_path
  local developer_dir
  local swift_major

  _pocketcasts_xcode_candidates=()

  if [[ -n "$requested_version" ]]; then
    _pocketcasts_add_xcode_candidate "/Applications/Xcode-$requested_version.app"
    _pocketcasts_add_xcode_candidate "/Applications/Xcode_$requested_version.app"
    _pocketcasts_add_xcode_candidate "/Applications/Xcode $requested_version.app"

    if [[ "$requested_version" == *.*.* ]]; then
      requested_major_minor="${requested_version%.*}"
      _pocketcasts_add_xcode_candidate "/Applications/Xcode-$requested_major_minor.app"
      _pocketcasts_add_xcode_candidate "/Applications/Xcode_$requested_major_minor.app"
      _pocketcasts_add_xcode_candidate "/Applications/Xcode $requested_major_minor.app"
    fi
  fi

  while IFS= read -r app_path; do
    _pocketcasts_add_xcode_candidate "$app_path"
  done < <(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' 2>/dev/null | sort)

  for app_path in "${_pocketcasts_xcode_candidates[@]}"; do
    developer_dir="$app_path/Contents/Developer"
    swift_major="$(_pocketcasts_swift_major "$developer_dir")"

    if [[ "$swift_major" =~ ^[0-9]+$ && "$swift_major" -ge 6 ]]; then
      echo "$developer_dir"
      return 0
    fi
  done

  return 1
}

_pocketcasts_select_xcode_main() {
  local script_dir
  local repo_root
  local xcode_version_file
  local requested_xcode_version=""
  local active_swift_major
  local selected_developer_dir

  if [[ "${POCKET_CASTS_XCODE_SELECTED:-}" == "1" ]]; then
    return 0
  fi

  export POCKET_CASTS_XCODE_SELECTED=1

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/../.." && pwd)"
  xcode_version_file="$repo_root/.xcode-version"

  if [[ -s "$xcode_version_file" ]]; then
    requested_xcode_version="$(sed -E 's/^~> ?//' "$xcode_version_file" | tr -d '[:space:]')"
  fi

  if ! command -v xcodebuild >/dev/null 2>&1; then
    return 0
  fi

  echo "Selecting Xcode"
  echo "Active developer directory: $(xcode-select --print-path 2>/dev/null || echo unavailable)"
  xcodebuild -version 2>/dev/null || echo "Active Xcode version unavailable"
  xcrun swift --version 2>/dev/null || swift --version 2>/dev/null || true

  active_swift_major="$(_pocketcasts_swift_major "${DEVELOPER_DIR:-}")"
  if [[ "$active_swift_major" =~ ^[0-9]+$ && "$active_swift_major" -ge 6 ]]; then
    return 0
  fi

  if selected_developer_dir="$(_pocketcasts_find_compatible_xcode "$requested_xcode_version")"; then
    export DEVELOPER_DIR="$selected_developer_dir"
    echo "Selected developer directory: $DEVELOPER_DIR"
    xcodebuild -version
    xcrun swift --version
    return 0
  fi

  cat <<EOF
Unable to find a Swift 6 capable Xcode.

The Modules and BuildTools packages depend on Swift 6 capable tooling, so
SwiftPM resolution can fail when the runner starts with an older toolchain.

Install an Xcode version compatible with $xcode_version_file or set
DEVELOPER_DIR to a Swift 6 capable Xcode before starting the GitHub runner.
EOF

  return 1
}

_pocketcasts_select_xcode_main
_pocketcasts_select_xcode_status="$?"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return "$_pocketcasts_select_xcode_status"
fi

exit "$_pocketcasts_select_xcode_status"
