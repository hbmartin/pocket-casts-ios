#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/select-xcode.sh"

cd "$REPO_ROOT"

"$SCRIPT_DIR/shared-setup.sh" --skip-gems

"$SCRIPT_DIR/prepare-credentials.sh"

source "$SCRIPT_DIR/ensure-mise.sh"

echo "Static checks"
mise run check:static
