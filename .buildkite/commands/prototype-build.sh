#!/bin/bash -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/select-xcode.sh"

if "$SCRIPT_DIR/should-skip-job.sh" --job-type build; then
  exit 0
fi

# Sentry CLI needs to be up-to-date
brew upgrade sentry-cli

"$SCRIPT_DIR/shared_setup.sh"

echo "--- :closed_lock_with_key: Installing Secrets"
bundle exec fastlane run configure_apply

echo "--- :hammer_and_wrench: Building"
bundle exec fastlane build_enterprise
