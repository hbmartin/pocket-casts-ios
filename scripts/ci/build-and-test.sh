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

"$SCRIPT_DIR/prepare-credentials.sh"

echo "Selecting an iOS Simulator"
DESTINATION="$(
  /usr/bin/ruby <<'RUBY'
require 'json'

devices_by_runtime = JSON.parse(`xcrun simctl list devices available --json`).fetch('devices')
requested_runtime_version = ENV['IOS_SIMULATOR_RUNTIME_VERSION']
candidates = []

devices_by_runtime.each do |runtime, devices|
  next unless runtime.include?('iOS')

  version = runtime.scan(/\d+/).map(&:to_i)
  version_string = version.join('.')
  next if requested_runtime_version && version_string != requested_runtime_version

  devices.each do |device|
    next unless device['isAvailable']
    next unless device['name'].start_with?('iPhone')

    preference = device['name'].include?(' Pro') ? 1 : 0
    candidates << [version, preference, device['name'], device['udid']]
  end
end

if candidates.empty?
  message = requested_runtime_version ? "No available iPhone simulator found for iOS #{requested_runtime_version}" : 'No available iPhone simulator found'
  abort(message)
end

selected = candidates.max_by { |version, preference, name, _udid| [version, preference, name] }
puts "platform=iOS Simulator,id=#{selected[3]}"
RUBY
)"
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
