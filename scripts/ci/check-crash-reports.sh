#!/bin/bash
# Crash-report sweep: fail test runs that leave crash reports behind even when
# every suite reports green (intermittent races can kill the test-host app
# between or after tests without failing xcodebuild — this is the only signal).
#
# Usage:
#   check-crash-reports.sh snapshot <state-file> [process-prefix]
#   check-crash-reports.sh check    <state-file> [process-prefix]
#
# snapshot: record the currently-present crash reports.
# check:    exit 1, listing any crash reports that appeared since the snapshot.
set -euo pipefail

MODE="${1:?usage: check-crash-reports.sh snapshot|check <state-file> [process-prefix]}"
STATE_FILE="${2:?usage: check-crash-reports.sh snapshot|check <state-file> [process-prefix]}"
PROCESS_PREFIX="${3:-podcasts}"

list_reports() {
    # Host-side reports (simulator processes report here) plus any per-device
    # report directories. Directories may not exist on fresh machines/CI.
    {
        ls "$HOME/Library/Logs/DiagnosticReports/$PROCESS_PREFIX"*.ips 2>/dev/null || true
        find "$HOME/Library/Developer/CoreSimulator/Devices" \
            -path "*/data/Library/Logs/DiagnosticReports/$PROCESS_PREFIX*.ips" 2>/dev/null || true
    } | sort -u
}

case "$MODE" in
    snapshot)
        list_reports > "$STATE_FILE"
        ;;
    check)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "check-crash-reports: no snapshot at $STATE_FILE (run 'snapshot' first)" >&2
            exit 2
        fi
        NEW_REPORTS=$(comm -13 "$STATE_FILE" <(list_reports))
        if [[ -n "$NEW_REPORTS" ]]; then
            echo "Crash reports appeared during this run (a process died even if suites passed):" >&2
            while IFS= read -r report; do
                echo "  $report" >&2
                # Surface the signal and the first app frames for triage.
                python3 - "$report" <<'PY' >&2 || true
import json, sys
lines = open(sys.argv[1]).read().split("\n", 1)
body = json.loads(lines[1])
exc = body.get("exception", {})
print(f"    {exc.get('signal', '?')} {exc.get('type', '')}")
ft = body.get("faultingThread", 0)
for frame in body["threads"][ft]["frames"][:6]:
    image = body["usedImages"][frame["imageIndex"]]
    print(f"    {image.get('name', '?')} {frame.get('symbol', '?')}")
PY
            done <<< "$NEW_REPORTS"
            exit 1
        fi
        echo "No new $PROCESS_PREFIX crash reports."
        ;;
    *)
        echo "check-crash-reports: unknown mode '$MODE'" >&2
        exit 2
        ;;
esac
