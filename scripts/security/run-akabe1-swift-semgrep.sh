#!/usr/bin/env bash
set -euo pipefail

readonly default_rules_repo="https://github.com/akabe1/akabe1-semgrep-rules.git"
readonly default_rules_ref="db843f16c4a740c22d97c489d176ff663c1776b6"
readonly cache_root="/tmp/pocketcasts-semgrep-rules"

rules_repo="${SEMGREP_SWIFT_RULES_REPO:-$default_rules_repo}"
rules_ref="${SEMGREP_SWIFT_RULES_REF:-$default_rules_ref}"
rules_checkout="${SEMGREP_SWIFT_RULES_CHECKOUT:-$cache_root/akabe1-semgrep-rules}"

if ! command -v git >/dev/null 2>&1; then
    echo "error: git is required to fetch the Swift Semgrep rules" >&2
    exit 127
fi

if ! command -v semgrep >/dev/null 2>&1; then
    echo "error: semgrep is required. Install it from https://semgrep.dev/docs/getting-started/" >&2
    exit 127
fi

mkdir -p "$cache_root"

if [[ ! -d "$rules_checkout/.git" ]]; then
    git init -q "$rules_checkout"
    git -C "$rules_checkout" remote add origin "$rules_repo"
else
    existing_origin="$(git -C "$rules_checkout" remote get-url origin)"
    if [[ "$existing_origin" != "$rules_repo" ]]; then
        git -C "$rules_checkout" remote set-url origin "$rules_repo"
    fi
fi

git -C "$rules_checkout" fetch --quiet --depth 1 origin "$rules_ref"
git -C "$rules_checkout" checkout -q --detach FETCH_HEAD

rules_dir="$rules_checkout/ios/swift"
if [[ ! -d "$rules_dir" ]]; then
    echo "error: Swift Semgrep rule directory not found at $rules_dir" >&2
    exit 1
fi

semgrep_args=(
    scan
    --config "$rules_dir"
    --include "*.swift"
    --metrics off
    --timeout 0
)

if [[ "${SEMGREP_SWIFT_ERROR:-0}" == "1" ]]; then
    semgrep_args+=(--error)
fi

exec semgrep "${semgrep_args[@]}" "$@"
