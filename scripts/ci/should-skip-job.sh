#!/usr/bin/env bash
set -euo pipefail

# Usage: should-skip-job.sh --job-type [build|localization]
# Return codes:
# 0  - Job should be skipped.
# 1  - Job should not be skipped.
# 15 - Error in script parameters.

COMMON_PATTERNS=(
  "*.md"
  "*.po"
  "*.pot"
  "*.txt"
  ".gitignore"
  "config/Version.xcconfig"
  "fastlane/**"
  "Gemfile"
  "Gemfile.lock"
)

LOCALIZATION_PATTERNS=(
  "**/*.strings"
  "**/*.stringsdict"
)

BUILD="build"
LOCALIZATION="localization"

is_pull_request_build() {
  [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]
}

changed_files() {
  local base_branch=""

  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    base_branch="${GITHUB_BASE_REF:-}"
  fi

  if [[ -z "$base_branch" ]]; then
    return 1
  fi

  git fetch --no-tags --quiet origin "$base_branch" || return 1
  git diff --name-only "origin/$base_branch"...HEAD || return 1
}

matches_any_pattern() {
  local file="$1"
  shift

  local pattern
  for pattern in "$@"; do
    if [[ "$file" == $pattern ]]; then
      return 0
    fi
  done

  return 1
}

any_changed_file_matches() {
  local patterns=("$@")
  local files
  local file

  if ! files="$(changed_files)"; then
    echo "Unable to determine changed files; running job." >&2
    return 0
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if matches_any_pattern "$file" "${patterns[@]}"; then
      return 0
    fi
  done <<< "$files"

  return 1
}

all_changed_files_match() {
  local patterns=("$@")
  local files
  local file
  local saw_file=1

  if ! files="$(changed_files)"; then
    echo "Unable to determine changed files; running job." >&2
    return 1
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    saw_file=0
    if ! matches_any_pattern "$file" "${patterns[@]}"; then
      return 1
    fi
  done <<< "$files"

  return "$saw_file"
}

show_skip_message() {
  local job_type=$1
  local label="${GITHUB_JOB:-$job_type}"
  local message="Skipped ${label} - no relevant files changed"

  echo "$message"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Skipped job"
      echo
      echo "$message"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

if [[ -z "${1:-}" || "$1" != "--job-type" || -z "${2:-}" ]]; then
  echo "Error: Must specify --job-type [$BUILD|$LOCALIZATION]"
  exit 15
fi

# Skip decisions are only safe for automatic PR builds. Branch and manual runs
# should run because there is no clear target branch in every case.
if ! is_pull_request_build; then
  exit 1
fi

job_type="$2"
case "$job_type" in
  "$LOCALIZATION")
    if ! any_changed_file_matches "${LOCALIZATION_PATTERNS[@]}"; then
      show_skip_message "$job_type"
      exit 0
    fi
    exit 1
    ;;
  "$BUILD")
    if all_changed_files_match "${COMMON_PATTERNS[@]}"; then
      show_skip_message "$job_type"
      exit 0
    fi
    exit 1
    ;;
  *)
    echo "Error: Job type must be either '$BUILD' or '$LOCALIZATION'"
    exit 15
    ;;
esac
