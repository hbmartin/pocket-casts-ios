#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/select-xcode.sh"

cd "$REPO_ROOT"

"$SCRIPT_DIR/shared-setup.sh" --skip-gems

"$SCRIPT_DIR/prepare-credentials.sh"

if ! command -v semgrep >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing Semgrep"
    brew install semgrep
  else
    echo "semgrep is required for make static_checks, but Homebrew is unavailable."
    exit 1
  fi
fi

echo "Static checks"
make static_checks
