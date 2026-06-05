#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

"$SCRIPT_DIR/shared_setup.sh" --skip-gems

echo "--- :closed_lock_with_key: Generating open-source credentials"
make external_contributor

if ! command -v semgrep >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "--- :homebrew: Installing Semgrep"
    brew install semgrep
  else
    echo "semgrep is required for make static_checks, but Homebrew is unavailable."
    exit 1
  fi
fi

echo "--- :mag: Static checks"
make static_checks
