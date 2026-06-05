#!/usr/bin/env bash
set -euo pipefail

git config user.name "${GIT_USER_NAME:-Buildkite}"
git config user.email "${GIT_USER_EMAIL:-buildkite@users.noreply.github.com}"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-hbmartin/pocket-casts-ios}"
  git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi
