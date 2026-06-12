#!/usr/bin/env bash
# Source this before using mise on CI. Installs mise if missing, then installs
# the tools pinned in mise.toml (idempotent; cached on self-hosted runners).

ENSURE_MISE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v mise >/dev/null 2>&1; then
  if [[ -x "$HOME/.local/bin/mise" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  elif command -v brew >/dev/null 2>&1; then
    echo "Installing mise"
    brew install mise
  else
    echo "mise is required but neither mise nor Homebrew is available." >&2
    echo "Install mise on this runner: https://mise.jdx.dev/getting-started.html" >&2
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
      return 1
    fi
    exit 1
  fi
fi

export MISE_YES=1
mise trust --quiet "$ENSURE_MISE_REPO_ROOT/mise.toml"
mise install --cd "$ENSURE_MISE_REPO_ROOT"
