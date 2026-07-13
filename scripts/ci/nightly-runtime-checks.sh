#!/usr/bin/env bash
# Nightly runtime checks: Thread Sanitizer over the unit suites, the suites on
# every installed iOS simulator runtime, and the UI smoke plan. These catch the
# classes of bug per-PR CI structurally misses: data races that need TSan,
# runtime-version-dependent concurrency behavior (isolated deinit differs by
# OS runtime), and launch-path regressions.
#
# MODE (first argument):
#   tsan            Thread Sanitizer over the UnitTests plan (RUNTIME_VERSION env)
#   runtime-matrix  plain unit suite on RUNTIME_VERSION (env, required)
#   smoke-ui        SmokeUITests test plan on RUNTIME_VERSION
#   perf-ui         PerformanceUITests plan + reporting-only delta table
#   live-staging-ui LiveStagingUITests test plan on RUNTIME_VERSION
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/select-xcode.sh"

cd "$REPO_ROOT"
MODE="${1:?usage: nightly-runtime-checks.sh tsan|runtime-matrix|smoke-ui|live-staging-ui}"
mkdir -p build/github/logs

"$SCRIPT_DIR/shared-setup.sh" --skip-gems
"$SCRIPT_DIR/prepare-credentials.sh"

DESTINATION="$(SIMULATOR_OS="${RUNTIME_VERSION:-18.6}" /usr/bin/ruby "$SCRIPT_DIR/select-ios-simulator.rb")"
echo "Using destination: $DESTINATION"

CRASH_STATE="$(mktemp)"
"$SCRIPT_DIR/check-crash-reports.sh" snapshot "$CRASH_STATE"

XCODEBUILD_ARGS=(
  test
  -project podcasts.xcodeproj
  -scheme "Pocket Casts Staging"
  -destination "$DESTINATION"
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=NO
)

case "$MODE" in
  tsan)
    if [[ -n "${ONLY_TESTING:-}" ]]; then
      XCODEBUILD_ARGS+=("-only-testing:$ONLY_TESTING")
    else
      XCODEBUILD_ARGS+=(-testPlan UnitTests)
    fi
    XCODEBUILD_ARGS+=(-enableThreadSanitizer YES)
    ;;
  runtime-matrix)
    if [[ -n "${ONLY_TESTING:-}" ]]; then
      XCODEBUILD_ARGS+=("-only-testing:$ONLY_TESTING")
    else
      XCODEBUILD_ARGS+=(-testPlan UnitTests)
    fi
    ;;
  smoke-ui)
    XCODEBUILD_ARGS+=(-testPlan SmokeUITests)
    ;;
  live-staging-ui)
    XCODEBUILD_ARGS+=(-testPlan LiveStagingUITests)
    ;;
  perf-ui)
    XCODEBUILD_ARGS+=(-testPlan PerformanceUITests)
    ;;
  *)
    echo "nightly-runtime-checks: unknown mode '$MODE'" >&2
    exit 2
    ;;
esac

TEST_STATUS=0
set -o pipefail
xcodebuild "${XCODEBUILD_ARGS[@]}" \
  2>&1 | tee "build/github/logs/nightly-$MODE-${RUNTIME_VERSION:-18.6}.log" || TEST_STATUS=$?

# Reporting-only perf table (Deferred Item 39): never affects TEST_STATUS.
if [ "$MODE" = "perf-ui" ]; then
  /usr/bin/ruby "$SCRIPT_DIR/perf-report.rb" "build/github/logs/nightly-$MODE-${RUNTIME_VERSION:-18.6}.log" \
    | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
fi

echo "Check for crash reports left behind by the run"
"$SCRIPT_DIR/check-crash-reports.sh" check "$CRASH_STATE"

exit "$TEST_STATUS"
