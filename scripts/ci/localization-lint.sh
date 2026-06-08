#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if "$SCRIPT_DIR/should-skip-job.sh" --job-type localization; then
  exit 0
fi

cd "$REPO_ROOT"

echo "Lint localized strings"
find podcasts \
  \( -name "*.strings" -o -name "*.stringsdict" \) \
  -print0 \
  | xargs -0 -n 1 plutil -lint
