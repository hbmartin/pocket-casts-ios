#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

if [[ "${BUILDKITE_PULL_REQUEST:-false}" == "false" ]]; then
  echo "Not a pull request build; skipping Danger."
  exit 0
fi

if [[ -z "${DANGER_GITHUB_API_TOKEN:-}" && -z "${DANGER_GITHUB_BEARER_TOKEN:-}" ]]; then
  message="Skipped Danger because DANGER_GITHUB_API_TOKEN is not configured."
  echo "$message"
  if command -v buildkite-agent >/dev/null 2>&1; then
    echo "$message" | buildkite-agent annotate --style info --context danger-token
  fi
  exit 0
fi

"$SCRIPT_DIR/shared_setup.sh" --skip-swiftpm

echo "--- :danger: Danger"
bundle exec danger
