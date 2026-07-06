#!/usr/bin/env bash
# Launch smoke test: install the built app on a simulator, launch it, and fail
# if the process dies or leaves a crash report within the settle window. Unit
# tests cannot catch launch-path crashes that race app startup (background
# launch work, notification delivery, executor assertions) — this can.
#
# Usage: smoke-launch.sh <app-path> [udid] [settle-seconds] [screenshot-path]
#   app-path        path to the built .app bundle (simulator slice)
#   udid            simulator UDID; defaults to select-ios-simulator.rb's pick
#   settle-seconds  how long the app must stay alive (default 30)
#   screenshot-path optional PNG destination captured before terminating
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_PATH="${1:?usage: smoke-launch.sh <app-path> [udid] [settle-seconds] [screenshot-path]}"
UDID="${2:-}"
SETTLE_SECONDS="${3:-30}"
SCREENSHOT_PATH="${4:-}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "smoke-launch: no app bundle at $APP_PATH" >&2
    exit 2
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Info.plist")"

if [[ -z "$UDID" ]]; then
    DESTINATION="$(/usr/bin/ruby "$SCRIPT_DIR/select-ios-simulator.rb")"
    UDID="${DESTINATION##*id=}"
fi

echo "smoke-launch: $BUNDLE_ID on simulator $UDID (settle ${SETTLE_SECONDS}s)"

xcrun simctl bootstatus "$UDID" -b

CRASH_STATE="$(mktemp)"
"$SCRIPT_DIR/check-crash-reports.sh" snapshot "$CRASH_STATE"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_PATH"
PID="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" | awk -F': ' '{print $2}')"
echo "smoke-launch: launched pid $PID"

sleep "$SETTLE_SECONDS"

STATUS=0
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "smoke-launch: FAIL — app process $PID died within ${SETTLE_SECONDS}s of launch" >&2
    STATUS=1
fi

if [[ -n "$SCREENSHOT_PATH" && "$STATUS" -eq 0 ]]; then
    xcrun simctl io "$UDID" screenshot "$SCREENSHOT_PATH" || true
fi

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
# Termination is SIGKILL and must not be misread as a crash; give ReportCrash a
# beat, then sweep. A report from the settle window fails the run even if the
# process was still alive at the deadline (e.g. a crashed relaunch).
sleep 2
if ! "$SCRIPT_DIR/check-crash-reports.sh" check "$CRASH_STATE"; then
    STATUS=1
fi

if [[ "$STATUS" -eq 0 ]]; then
    echo "smoke-launch: OK — alive after ${SETTLE_SECONDS}s, no crash reports"
fi
exit "$STATUS"
