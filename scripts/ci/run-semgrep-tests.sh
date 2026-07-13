#!/bin/sh
# Runs the Semgrep rule unit tests against the fixtures under semgrep/tests.
# Single source of truth shared by `mise run semgrep:tests` and the Semgrep
# GitHub workflow. Fixtures are listed explicitly (rather than scanning the
# directory) because each one is tied to a specific rule config.
set -eu

cd "$(dirname "$0")/../.."

run_fixture() {
  config="$1"
  fixture="$2"
  if [ ! -e "$fixture" ]; then
    echo "Missing Semgrep test fixture: $fixture (remove it from $0 or restore the file)" >&2
    exit 1
  fi
  semgrep test --config "$config" "$fixture"
}

run_fixture semgrep/pocket-casts.yml semgrep/tests/pocket-casts-web-opening.swift
run_fixture semgrep/swift-datamodel-sql.yml semgrep/tests/swift-datamodel-sql.swift

for fixture in \
  semgrep/tests/mise.toml \
  semgrep/tests/swift-security-insecure-storage.swift \
  semgrep/tests/pocket-casts-keychain.swift \
  semgrep/tests/swift-security-urlhelper.swift \
  semgrep/tests/swift-security-concurrency.swift \
  semgrep/tests/swift-security-audio-realtime.swift \
  semgrep/tests/swift-security-crypto.swift \
  semgrep/tests/swift-security-pr-feedback.swift \
  semgrep/tests/swift-security-sql-interpolation.swift \
  semgrep/tests/swift-security-fire-and-forget-save.swift \
  semgrep/tests/swift-security-test-network-urls.swift \
  semgrep/tests/swift-security-concurrency-escape-hatches.swift \
  semgrep/tests/swift-security-unchecked-sendable.swift \
  semgrep/tests/swift-playlist-typed-requests.swift \
  semgrep/tests/swift-custom-query-validator.swift \
  semgrep/tests/Modules/Sources/PocketCastsServer/ServerPostOnMainFixture.swift \
  semgrep/tests/podcasts/IsolatedDeinitFixture.swift \
  semgrep/tests/github-actions-security.yml \
  semgrep/tests/podcasts/Main/MainTabBarController.swift \
  semgrep/tests/podcasts/ProfileViewController.swift \
  semgrep/tests/podcasts/RemovedPlusLockedInfo.swift \
  semgrep/tests/podcasts/RemovedLegacyPayment.swift \
  semgrep/tests/podcasts/RemovedUserSatisfactionSurvey.swift \
  semgrep/tests/Modules/Sources/PocketCastsServer/TypedMessagePostFixture.swift \
  semgrep/tests/generate-credentials-placeholder-regex.sh
do
  run_fixture semgrep/swift-security.yml "$fixture"
done
