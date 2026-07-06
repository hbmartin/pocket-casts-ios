#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/select-xcode.sh"

if "$SCRIPT_DIR/should-skip-job.sh" --job-type build; then
  exit 0
fi

cd "$REPO_ROOT"
DERIVED_DATA_PATH="${POCKET_CASTS_CI_DERIVED_DATA_PATH:-build/github/DerivedData}"
mkdir -p build/github/logs build/github/results
mkdir -p "$DERIVED_DATA_PATH"
rm -rf build/github/results/PocketCastsTests.xcresult

"$SCRIPT_DIR/shared-setup.sh" --skip-gems

"$SCRIPT_DIR/prepare-credentials.sh"

echo "Selecting an iOS Simulator"
DESTINATION="$(/usr/bin/ruby "$SCRIPT_DIR/select-ios-simulator.rb")"
echo "Using destination: $DESTINATION"

echo "Xcode"
xcodebuild -version

echo "Build and test staging"
echo "Using DerivedData path: $DERIVED_DATA_PATH"
XCODEBUILD_ARGS=(
  test
  -project podcasts.xcodeproj
  -scheme "Pocket Casts Staging"
  -configuration StagingDebug
  "-only-testing:${ONLY_TESTING:-PocketCastsTests}"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -resultBundlePath build/github/results/PocketCastsTests.xcresult
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=NO
)

if [[ -n "${POCKET_CASTS_CI_OTHER_SWIFT_FLAGS:-}" ]]; then
  XCODEBUILD_ARGS+=(OTHER_SWIFT_FLAGS="${POCKET_CASTS_CI_OTHER_SWIFT_FLAGS}")
fi

CRASH_STATE="$(mktemp)"
"$SCRIPT_DIR/check-crash-reports.sh" snapshot "$CRASH_STATE"

set -o pipefail
xcodebuild "${XCODEBUILD_ARGS[@]}" \
  2>&1 | tee build/github/logs/test-staging.log

echo "Check for crash reports left behind by the test run"
"$SCRIPT_DIR/check-crash-reports.sh" check "$CRASH_STATE"

echo "Check strict-concurrency warnings"
scripts/ci/check-concurrency-warnings.sh build/github/logs/test-staging.log

echo "Launch smoke test"
SIMULATOR_UDID="${DESTINATION##*id=}"
"$SCRIPT_DIR/smoke-launch.sh" \
  "$DERIVED_DATA_PATH/Build/Products/StagingDebug-iphonesimulator/podcasts.app" \
  "$SIMULATOR_UDID" \
  "${POCKET_CASTS_SMOKE_SETTLE_SECONDS:-30}" \
  build/github/results/smoke-launch.png
