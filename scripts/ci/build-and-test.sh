#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/select-xcode.sh"

if "$SCRIPT_DIR/should-skip-job.sh" --job-type build; then
  exit 0
fi

cd "$REPO_ROOT"
mkdir -p build/github/logs build/github/results
rm -rf build/github/results/PocketCastsTests.xcresult

"$SCRIPT_DIR/shared-setup.sh" --skip-gems

echo "Generating open-source credentials"
make external_contributor

echo "Selecting an iOS Simulator"
DESTINATION="$(/usr/bin/ruby "$SCRIPT_DIR/select-ios-simulator.rb")"
echo "Using destination: $DESTINATION"

echo "Xcode"
xcodebuild -version

echo "Build and test staging"
set -o pipefail
xcodebuild test \
  -project podcasts.xcodeproj \
  -scheme "Pocket Casts Staging" \
  -configuration StagingDebug \
  "-only-testing:${ONLY_TESTING:-PocketCastsTests}" \
  -destination "$DESTINATION" \
  -derivedDataPath build/github/DerivedData \
  -resultBundlePath build/github/results/PocketCastsTests.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/github/logs/test-staging.log
