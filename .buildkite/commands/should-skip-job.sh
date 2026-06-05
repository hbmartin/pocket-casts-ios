#!/usr/bin/env bash
set -euo pipefail

# Usage: should-skip-job.sh --job-type [build|localization]
# --job-type build: skip PR builds when changes are limited to documentation,
#     tooling, and non-code files.
# --job-type localization: skip PR builds when no localization files changed.
#
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

buildkite_annotate() {
  local style="$1"
  local context="$2"
  local message="$3"

  if command -v buildkite-agent >/dev/null 2>&1; then
    echo "$message" | buildkite-agent annotate --style "$style" --context "$context"
  fi
}

buildkite_cancel_step() {
  if command -v buildkite-agent >/dev/null 2>&1; then
    buildkite-agent step cancel
  fi
}

changed_files() {
  if [[ "${BUILDKITE_PULL_REQUEST:-false}" == "false" ]]; then
    return 1
  fi

  local base_branch="${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-${BUILDKITE_BRANCH:-}}"
  if [[ -z "$base_branch" ]]; then
    return 1
  fi

  git fetch --no-tags --quiet origin "$base_branch"
  git diff --name-only "origin/$base_branch"...HEAD
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
  local file

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if matches_any_pattern "$file" "${patterns[@]}"; then
      return 0
    fi
  done < <(changed_files)

  return 1
}

all_changed_files_match() {
  local patterns=("$@")
  local file
  local saw_file=1

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    saw_file=0
    if ! matches_any_pattern "$file" "${patterns[@]}"; then
      return 1
    fi
  done < <(changed_files)

  return "$saw_file"
}

show_skip_message() {
  local job_type=$1
  local message="Skipped ${BUILDKITE_LABEL:-Job} - no relevant files changed"
  local context="skip-$(echo "${BUILDKITE_LABEL:-$job_type}" | sed -E -e 's/[^[:alnum:]]+/-/g' | tr A-Z a-z)"

  buildkite_annotate "info" "$context" "$message"
  echo "$message"
}

if [[ -z "${1:-}" || "$1" != "--job-type" || -z "${2:-}" ]]; then
  echo "Error: Must specify --job-type [$BUILD|$LOCALIZATION]"
  buildkite_cancel_step
  exit 15
fi

# Always run branch builds. Skip decisions are only safe for PR builds because
# Buildkite exposes a clear target branch for them.
if [[ "${BUILDKITE_PULL_REQUEST:-false}" == "false" ]]; then
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
    buildkite_cancel_step
    exit 15
    ;;
esac
