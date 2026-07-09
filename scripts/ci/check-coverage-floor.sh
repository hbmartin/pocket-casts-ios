#!/usr/bin/env bash
# Code-coverage floor ratchet for CI.
#
# Reads the aggregate line coverage of first-party targets from the test run's
# .xcresult bundle (via `xcrun xccov`) and fails if it drops below the floor in
# scripts/ci/coverage-floor.txt. Test bundles (*.xctest) are excluded from the
# aggregate so covered test code does not inflate the number.
#
# The floor is a ratchet: it only moves up. When coverage grows comfortably past
# the floor (>= 1 point of headroom), the check prints a reminder to raise it.
# Never lower the floor to make a PR pass — add or fix tests instead.
#
# Usage: check-coverage-floor.sh [--json-report <file>] <xcresult-path> [floor-file]
#   --json-report  use a pre-extracted `xccov view --report --json` file instead
#                  of invoking xccov (used by the script tests)
set -euo pipefail

json_report=""
if [[ "${1:-}" == "--json-report" ]]; then
  json_report="${2:?--json-report requires a file argument}"
  shift 2
fi

xcresult_path="${1:-}"
if [[ -z "$json_report" && -z "$xcresult_path" ]]; then
  echo "usage: check-coverage-floor.sh [--json-report <file>] <xcresult-path> [floor-file]" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
floor_file="${2:-$script_dir/coverage-floor.txt}"

if [[ ! -f "$floor_file" ]]; then
  echo "Coverage floor file not found: $floor_file" >&2
  exit 2
fi

# First non-comment, non-blank line is the floor percentage.
floor="$(grep -Ev '^[[:space:]]*(#|$)' "$floor_file" | head -n 1 | tr -d '[:space:]')"
if ! [[ "$floor" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Coverage floor file must contain a numeric percentage, got: '$floor'" >&2
  exit 2
fi

if [[ -n "$json_report" ]]; then
  report_json="$(cat "$json_report")"
else
  if [[ ! -e "$xcresult_path" ]]; then
    echo "xcresult bundle not found: $xcresult_path" >&2
    exit 2
  fi
  report_json="$(xcrun xccov view --report --json "$xcresult_path")"
fi

coverage="$(printf '%s' "$report_json" | ruby -rjson -e '
  report = JSON.parse($stdin.read)
  targets = (report["targets"] || []).reject { |t| t["name"].to_s.end_with?(".xctest") }
  covered = targets.sum { |t| t["coveredLines"].to_i }
  executable = targets.sum { |t| t["executableLines"].to_i }
  pct = executable.zero? ? 0.0 : covered.to_f / executable * 100
  printf("%.2f\n", pct)
')"

echo "Aggregate first-party line coverage: ${coverage}% (floor: ${floor}%)"

if awk -v cov="$coverage" -v floor="$floor" 'BEGIN { exit !(cov < floor) }'; then
  echo "Coverage ${coverage}% is below the floor of ${floor}%." >&2
  echo "Add tests for the code you changed. Do not lower ${floor_file##*/} to make this pass." >&2
  exit 1
fi

if awk -v cov="$coverage" -v floor="$floor" 'BEGIN { exit !(cov >= floor + 1.0) }'; then
  echo "Info: coverage is at ${coverage}% vs floor ${floor}% — consider ratcheting the floor up in ${floor_file##*/} (keep ~0.5 points of headroom for run-to-run noise)."
fi

echo "Coverage floor check passed."
