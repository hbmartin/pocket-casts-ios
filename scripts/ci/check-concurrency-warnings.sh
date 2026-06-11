#!/usr/bin/env bash
# Fails if an xcodebuild log contains strict-concurrency warnings under Modules/Sources.
#
# The Modules package opts into StrictConcurrency (Swift 5 language mode), so these
# diagnostics are warnings and would otherwise regress silently. Incremental builds only
# re-emit warnings for recompiled files, which is sufficient for regression detection:
# introducing a warning requires changing a file, and changed files are recompiled.
#
# Usage: check-concurrency-warnings.sh <xcodebuild-log-file>

set -euo pipefail

log_file="${1:?usage: check-concurrency-warnings.sh <xcodebuild-log-file>}"

warnings="$(grep -E "Modules/Sources/.*\.swift:[0-9]+:[0-9]+: warning:" "$log_file" \
  | grep -iE "sendable|concurrency|actor|isolated|data race|sending" \
  | sort -u || true)"

if [[ -n "$warnings" ]]; then
  echo "Strict-concurrency warnings detected under Modules/Sources:" >&2
  echo "$warnings" >&2
  exit 1
fi

echo "No strict-concurrency warnings under Modules/Sources."
