#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
rules_config="${SEMGREP_SWIFT_RULES_CONFIG:-$repo_root/semgrep/swift-security.yml}"

if ! command -v semgrep >/dev/null 2>&1; then
    echo "error: semgrep is required. Install it from https://semgrep.dev/docs/getting-started/" >&2
    exit 127
fi

if [[ ! -f "$rules_config" ]]; then
    echo "error: Swift Semgrep rule config not found at $rules_config" >&2
    exit 1
fi

semgrep_args=(
    scan
    --config "$rules_config"
    --include "*.swift"
    --metrics off
    --timeout 0
    --disable-version-check
)

if [[ "${SEMGREP_SWIFT_ERROR:-0}" == "1" ]]; then
    semgrep_args+=(--error)
fi

exec semgrep "${semgrep_args[@]}" "$@"
