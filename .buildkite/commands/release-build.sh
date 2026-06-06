#!/bin/bash -eu

# Ensure we get the latest commit of the `release/*` branch, especially to get last version bump commit before building the release
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_VERSION="${1:?RELEASE_VERSION parameter missing}"
source "$SCRIPT_DIR/select-xcode.sh"

"$SCRIPT_DIR/checkout-release-branch.sh" "$RELEASE_VERSION"

"$SCRIPT_DIR/shared_setup.sh"

echo "--- :closed_lock_with_key: Installing Secrets"
bundle exec fastlane run configure_apply

echo "--- :hammer_and_wrench: Building"
bundle exec fastlane build_app_store_connect
