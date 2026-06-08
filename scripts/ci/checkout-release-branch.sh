#!/usr/bin/env bash
set -euo pipefail

echo "Checkout release branch"

if [[ -n "${1:-}" ]]; then
  RELEASE_VERSION="$1"
elif [[ "${GITHUB_REF_NAME:-}" =~ ^release/ ]]; then
  RELEASE_VERSION="${GITHUB_REF_NAME#release/}"
else
  echo "Error: RELEASE_VERSION parameter missing and current ref is not a release branch" >&2
  exit 1
fi

BRANCH_NAME="release/${RELEASE_VERSION}"

git fetch origin "$BRANCH_NAME"
git checkout -B "$BRANCH_NAME" FETCH_HEAD
