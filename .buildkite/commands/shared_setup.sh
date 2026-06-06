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
  echo "--- :ruby: Setting up Ruby tools"

  if command -v rbenv >/dev/null 2>&1 && [[ -s "$REPO_ROOT/.ruby-version" ]]; then
    RUBY_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/.ruby-version")"

    if ! rbenv versions --bare | grep -qx "$RUBY_VERSION"; then
      if command -v ruby-build >/dev/null 2>&1; then
        rbenv install -s "$RUBY_VERSION"
      else
        echo "rbenv is installed, but Ruby $RUBY_VERSION is not and ruby-build is unavailable."
        echo "Install Ruby $RUBY_VERSION on this agent or remove rbenv from the agent environment."
        exit 1
      fi
    fi

    export RBENV_VERSION="$RUBY_VERSION"
    eval "$(rbenv init - bash)"
    rbenv rehash
  fi

  if ! bundle --version >/dev/null 2>&1; then
    gem install bundler
  fi

  bundle check || bundle install --jobs "${BUNDLE_JOBS:-4}" --retry "${BUNDLE_RETRY:-3}"
fi

if [[ "$RESOLVE_SWIFTPM" -eq 1 ]]; then
  echo "--- :swift: Resolving Swift Package Manager dependencies"
  swift package --package-path "$REPO_ROOT/Modules" resolve
  swift package --package-path "$REPO_ROOT/BuildTools" resolve
fi
