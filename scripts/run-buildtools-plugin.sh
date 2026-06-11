#!/usr/bin/env bash
# Runs a Swift package plugin from BuildTools with the macOS SDK selected.
# Usage: scripts/run-buildtools-plugin.sh <plugin> [args...]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../BuildTools"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT

swift package plugin \
  --allow-writing-to-directory .. \
  --allow-writing-to-package-directory \
  "$@"
