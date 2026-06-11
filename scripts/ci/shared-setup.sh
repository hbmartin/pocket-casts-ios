#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/select-xcode.sh"

INSTALL_GEMS=1
RESOLVE_SWIFTPM=1

for arg in "$@"; do
  case "$arg" in
    --skip-gems)
      INSTALL_GEMS=0
      ;;
    --skip-swiftpm)
      RESOLVE_SWIFTPM=0
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

if [[ "$INSTALL_GEMS" -eq 1 ]]; then
  echo "Setting up Ruby tools"

  source "$SCRIPT_DIR/ensure-mise.sh"
  eval "$(mise env -s bash --cd "$REPO_ROOT")"

  if ! bundle --version >/dev/null 2>&1; then
    gem install bundler
  fi

  bundle check || bundle install --jobs "${BUNDLE_JOBS:-4}" --retry "${BUNDLE_RETRY:-3}"
fi

if [[ "$RESOLVE_SWIFTPM" -eq 1 ]]; then
  echo "Resolving Swift Package Manager dependencies"
  swift package --package-path "$REPO_ROOT/Modules" resolve
  swift package --package-path "$REPO_ROOT/BuildTools" resolve
fi
