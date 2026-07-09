#!/usr/bin/env bash
# Tests for scripts/ci/check-coverage-floor.sh using synthetic xccov JSON reports.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/ci/check-coverage-floor.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

failures=0

assert() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok: $label"
  else
    echo "FAIL: $label" >&2
    failures=$((failures + 1))
  fi
}

assert_fails() {
  local label="$1"
  shift
  if "$@"; then
    echo "FAIL: $label" >&2
    failures=$((failures + 1))
  else
    echo "ok: $label"
  fi
}

report="$tmp_dir/report.json"
floor="$tmp_dir/floor.txt"

# 150 covered / 1000 executable across app + module targets = 15.00%.
# The .xctest target is fully covered and must be excluded from the aggregate.
cat > "$report" <<'EOF'
{
  "targets": [
    { "name": "podcasts.app", "coveredLines": 50, "executableLines": 800 },
    { "name": "PocketCastsDataModel.framework", "coveredLines": 100, "executableLines": 200 },
    { "name": "PocketCastsTests.xctest", "coveredLines": 5000, "executableLines": 5000 }
  ]
}
EOF

# Coverage above the floor passes.
echo "14.0" > "$floor"
assert "coverage above floor passes" "$checker" --json-report "$report" unused.xcresult "$floor"

# Coverage below the floor fails.
echo "15.5" > "$floor"
assert_fails "coverage below floor fails" "$checker" --json-report "$report" unused.xcresult "$floor" 2>/dev/null

# Test bundles are excluded: with them included the aggregate would be ~85%.
echo "20.0" > "$floor"
assert_fails "xctest targets excluded from aggregate" "$checker" --json-report "$report" unused.xcresult "$floor" 2>/dev/null

# The reported percentage is the non-test aggregate.
echo "1.0" > "$floor"
out="$("$checker" --json-report "$report" unused.xcresult "$floor")"
assert "reports aggregate percentage" grep -q "15.00%" <<< "$out"

# Ample headroom prints a ratchet-up reminder; a tight floor does not.
assert "headroom suggests ratcheting up" grep -q "ratcheting the floor up" <<< "$out"
echo "14.5" > "$floor"
tight_out="$("$checker" --json-report "$report" unused.xcresult "$floor")"
assert_fails "tight floor has no ratchet reminder" grep -q "ratcheting the floor up" <<< "$tight_out"

# Comments and blank lines in the floor file are skipped.
printf '# comment\n\n14.0\n' > "$floor"
assert "floor file comments skipped" "$checker" --json-report "$report" unused.xcresult "$floor"

# A non-numeric floor is a configuration error.
echo "not-a-number" > "$floor"
assert_fails "non-numeric floor rejected" "$checker" --json-report "$report" unused.xcresult "$floor" 2>/dev/null

# An empty report (no coverage data) fails against a positive floor.
echo '{ "targets": [] }' > "$report"
echo "1.0" > "$floor"
assert_fails "empty report fails" "$checker" --json-report "$report" unused.xcresult "$floor" 2>/dev/null

if (( failures > 0 )); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "All check-coverage-floor tests passed."
