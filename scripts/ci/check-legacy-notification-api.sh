#!/usr/bin/env bash
# Grep ratchet for legacy NotificationCenter APIs (typed-notification migration,
# Phase 6). Fails on NEW occurrences of:
#
#   'addObserver(self, selector:'   selector-based NotificationCenter observers.
#                                   Only system notifications (keyboard, app
#                                   lifecycle) may still use these; app-domain
#                                   notifications must use typed message structs
#                                   (podcasts/Notifications/*.swift) observed via
#                                   addCustomObserver(_:handler:) or
#                                   NotificationCenter.default.addObserver(for:using:).
#   'postOnMainThread(notification:' the retired string-name post helper. Post
#                                   typed messages with
#                                   NotificationCenter.postOnMainThread(_:) instead.
#
# outside the checked-in allowlist (scripts/ci/legacy-notification-allowlist.txt),
# which baselines the remaining legitimate files. The allowlist is deletion-only:
# remove entries as files are converted; never add entries to admit new usage.
#
# Usage: check-legacy-notification-api.sh
# Env (for script tests): LEGACY_NOTIFICATION_REPO_ROOT, LEGACY_NOTIFICATION_ALLOWLIST
set -euo pipefail

# Stable sort order so output compares correctly in CI.
export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${LEGACY_NOTIFICATION_REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
allowlist_file="${LEGACY_NOTIFICATION_ALLOWLIST:-$script_dir/legacy-notification-allowlist.txt}"

if [[ ! -f "$allowlist_file" ]]; then
  echo "Allowlist file not found: $allowlist_file" >&2
  exit 1
fi

# Allowlist entries: repo-relative file paths; blank lines and # comments ignored.
allowed_files="$(grep -Ev '^[[:space:]]*(#|$)' "$allowlist_file" || true)"

# "path:line:content" matches in tracked Swift files, excluding semgrep rule
# fixtures and BuildTools (never first-party app code; same scope as the count
# ratchets in check-count-ratchets.sh).
matches="$(
  cd "$repo_root"
  git ls-files -z -- '*.swift' | while IFS= read -r -d '' f; do
    case "$f" in
      (semgrep/* | BuildTools/*) continue ;;
    esac
    printf '%s\0' "$f"
  done | xargs -0 grep -n -F -e 'addObserver(self, selector:' -e 'postOnMainThread(notification:' -- 2>/dev/null || true
)"

violations=""
if [[ -n "$matches" ]]; then
  while IFS= read -r match; do
    file="${match%%:*}"
    if ! grep -Fxq -- "$file" <<< "$allowed_files"; then
      violations+="  $match"$'\n'
    fi
  done <<< "$matches"
fi

# Deletion-only housekeeping: point out allowlist entries that no longer match.
stale=""
if [[ -n "$allowed_files" ]]; then
  while IFS= read -r file; do
    if ! grep -q -- "^$file:" <<< "$matches"; then
      stale+="  $file"$'\n'
    fi
  done <<< "$allowed_files"
fi
if [[ -n "$stale" ]]; then
  echo "Info: allowlist entries with no remaining legacy notification API usage —"
  echo "remove them from ${allowlist_file#"$repo_root"/}:"
  printf '%s' "$stale"
fi

if [[ -n "$violations" ]]; then
  echo "New legacy NotificationCenter API usage outside the allowlist:" >&2
  printf '%s' "$violations" >&2
  echo >&2
  echo "Use a typed message struct (podcasts/Notifications/*.swift or" >&2
  echo "Modules/Sources/PocketCastsServer/Public/ServerMessages.swift) with" >&2
  echo "addCustomObserver(_:handler:) / NotificationCenter.postOnMainThread(_:) instead." >&2
  echo "Only system-notification observers with no typed SDK message may be" >&2
  echo "allowlisted in ${allowlist_file#"$repo_root"/} (call it out in your PR)." >&2
  exit 1
fi

echo "OK [legacy-notifications]: no legacy NotificationCenter API usage outside the allowlist."
