# Getting Started

This guide covers the local developer setup needed to build, test, run, and
debug Pocket Casts for iOS on a Mac. It focuses on the day-to-day setup path for
new developers. For GitHub Actions self-hosted runner setup, see
[GitHubActionsLocalRunner.md](./GitHubActionsLocalRunner.md).

## Quick Start

From a clean checkout:

```bash
gem install bundler
make install_dependencies
make external_contributor
make build_staging
```

Then open `podcasts.xcodeproj` in Xcode, select the `Pocket Casts Staging`
scheme, choose an iPhone simulator, and run the app.

Before opening a pull request, run:

```bash
make format
make static_checks
make test_staging
```

## Local Mac Toolchain

Use a Mac with an Xcode version compatible with `.xcode-version`. The project
currently expects Xcode `26.4.1` or newer and a Swift 6 capable toolchain.

Check the active Xcode:

```bash
xcodebuild -version
xcode-select -p
```

If the wrong Xcode is selected:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
```

Install an iPhone simulator runtime through Xcode:

```text
Xcode > Settings > Components
```

Verify available iPhone simulators:

```bash
xcrun simctl list devices available
xcrun simctl list runtimes
```

The Makefile defaults to `SIMULATOR_OS=18.5` for test destinations. If your
installed runtime is different, pass the OS explicitly:

```bash
make test_staging SIMULATOR_OS=18.4
```

The repo's Ruby tooling expects the version in `.ruby-version`, currently
`3.2.2`. Using `rbenv` keeps the repo isolated from the system Ruby:

```bash
brew install rbenv ruby-build
rbenv install 3.2.2
rbenv local 3.2.2
rbenv exec gem install bundler
```

The Makefile runs Fastlane through:

```make
rbenv exec bundle exec fastlane
```

That means Ruby commands used by the project should work through `rbenv`.

Install Homebrew if needed, then install the local command-line tools that are
not managed by Bundler:

```bash
brew install semgrep
```

Protocol buffer updates need additional tools, but normal build and test work
does not:

```bash
brew install protobuf swift-protobuf
```

## Project Bootstrap

Install Bundler and the Ruby gems used by Fastlane:

```bash
gem install bundler
make install_dependencies
```

If you are an external contributor, or if your local secrets are not available
yet, generate placeholder credentials:

```bash
make external_contributor
```

This creates `podcasts/Credentials/LocalApiCredentials.swift` from
`podcasts/Credentials/ApiCredentials.tpl` and blanks the secret placeholders so
the app can build locally. External contributor credentials are enough for
normal staging builds and tests, but service-backed features that require real
API keys will be disabled or limited.

Useful first verification commands:

```bash
make help
make build_staging
make test_staging ONLY_TESTING=PocketCastsTests
```

If Swift Package Manager or Xcode indexing appears stuck after the first open,
try closing Xcode and resolving packages from the command line:

```bash
xcodebuild -resolvePackageDependencies -project podcasts.xcodeproj -scheme "Pocket Casts Staging"
```

Open the project file, not a workspace:

```bash
open podcasts.xcodeproj
```

Recommended first run in Xcode:

1. Select the `Pocket Casts Staging` scheme.
2. Select an installed iPhone simulator.
3. Build once with `Command-B`.
4. Run with `Command-R`.

Generated local files and derived state:

- `make external_contributor` writes
  `podcasts/Credentials/LocalApiCredentials.swift`.
- Xcode and Swift Package Manager write derived data outside the repository by
  default.
- `make generate_code` regenerates SwiftGen-managed resources.
- `make generate_colors` regenerates theme colors from
  `scripts/themes/theme.csv`.
- `make update_proto API_PATH=/path/to/proto` regenerates protobuf Swift files.

Do not commit local credentials, exported databases, logs, derived data, or
temporary build artifacts.

## Build, Test, And Static Checks

The Makefile wraps the common local commands. Prefer these targets because they
match CI more closely than ad hoc `xcodebuild` commands.

Build the staging app:

```bash
make build_staging
```

The plain debug build target is also available:

```bash
make build
```

Build and run all default staging unit tests:

```bash
make test_staging
```

The plain debug test target is also available:

```bash
make test
```

Use staging targets for normal development unless you are intentionally checking
behavior specific to the `pocketcasts` Debug scheme.

Run a single test class, method, or module:

```bash
make test_staging ONLY_TESTING=PocketCastsTests/YourTestClass/testMethodName
make test_staging ONLY_TESTING=PocketCastsDataModelTests
make test_staging ONLY_TESTING=PocketCastsServerTests
make test_staging ONLY_TESTING=PocketCastsUtilsTests
```

Format Swift code before sending a pull request:

```bash
make format
```

Run the full local static-check suite:

```bash
make static_checks
```

`make static_checks` runs:

- SwiftLint through the `BuildTools` Swift Package plugin.
- Semgrep rule tests.
- Swift/iOS security Semgrep rules from `semgrep/swift-security.yml`.
- Pocket Casts-specific Semgrep rules from `semgrep/pocket-casts.yml`.
- Xcode static analyzer for the staging app.

Run individual checks while iterating:

```bash
make lint
make semgrep_tests
make semgrep_swift_security
make semgrep_pocket_casts
make xcode_static_analyzer
```

Semgrep findings fail by default. For investigation only, run report-only scans:

```bash
SEMGREP_SWIFT_ERROR=0 make semgrep_swift_security
SEMGREP_POCKET_CASTS_ERROR=0 make semgrep_pocket_casts
```

See [Semgrep.md](./Semgrep.md) and [SecurityScanning.md](./SecurityScanning.md)
for rule authoring and security scanning details.

Clean build artifacts when local state looks suspect:

```bash
make clean
```

For deeper Xcode cleanup, remove the derived data path used by a specific manual
build or use Xcode's Derived Data UI. Avoid broad cleanup while Xcode or tests
are actively running.

## Running In Simulator From CLI

When launching from the command line, use an explicit simulator UDID. Generic
destinations can select the wrong simulator or architecture when multiple
matching devices are installed.

List available devices and copy the UDID for the simulator you want:

```bash
xcrun simctl list devices available
```

Boot the simulator if needed:

```bash
xcrun simctl boot <SIMULATOR_UDID>
open -a Simulator
```

If local secrets are missing, prepare placeholder credentials first:

```bash
make external_contributor
```

Build the staging app for the booted simulator with signing disabled:

```bash
set -o pipefail
xcodebuild -quiet -project podcasts.xcodeproj \
  -scheme "Pocket Casts Staging" \
  -configuration StagingDebug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/pocketcasts-sim-deriveddata \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  2>&1 | tee /tmp/pocketcasts-sim-build.log
```

Keep `set -o pipefail` when piping through `tee`; otherwise a failed
`xcodebuild` can look successful.

Install and launch the app:

```bash
xcrun simctl install <SIMULATOR_UDID> /tmp/pocketcasts-sim-deriveddata/Build/Products/StagingDebug-iphonesimulator/podcasts.app
xcrun simctl launch <SIMULATOR_UDID> au.com.shiftyjelly.podcasts
```

Stream simulator logs for the app:

```bash
xcrun simctl spawn <SIMULATOR_UDID> log stream --style compact --predicate 'process == "podcasts"'
```

If install fails, confirm the app bundle exists:

```bash
ls -la /tmp/pocketcasts-sim-deriveddata/Build/Products/StagingDebug-iphonesimulator/podcasts.app
```

If launch fails, check the installed bundle identifiers:

```bash
xcrun simctl get_app_container <SIMULATOR_UDID> au.com.shiftyjelly.podcasts app
```

Capture a simulator screenshot or recording when you need to attach evidence to
an issue or pull request:

```bash
xcrun simctl io <SIMULATOR_UDID> screenshot /tmp/pocketcasts-screenshot.png
xcrun simctl io <SIMULATOR_UDID> recordVideo /tmp/pocketcasts-recording.mov
```

Stop a recording with `Control-C`.

Send one of the checked-in sample push notification payloads to the simulator:

```bash
xcrun simctl push <SIMULATOR_UDID> au.com.shiftyjelly.podcasts scripts/notifications/signup.apns
```

If the simulator is in a bad state, shut it down and retry:

```bash
xcrun simctl shutdown <SIMULATOR_UDID>
xcrun simctl boot <SIMULATOR_UDID>
```

Erase a simulator only when you are comfortable losing its local app data:

```bash
xcrun simctl erase <SIMULATOR_UDID>
```

## Debugging And Support Workflows

### App Logs

Logs can be viewed and shared from inside the app:

```text
Profile > Help & Feedback > ... > Logs
```

When debugging analytics, enable the `analyticsLogging` feature flag to log
analytics events.

### Export And Import Bundles

Support and debugging often need an app export containing the database, settings
plist, and logs. Create one from either location:

```text
Profile > Help & Feedback > ... > Export Database
Profile > Settings > Developer > Export Bundle
```

Importing an export replaces the simulator or device database and settings after
confirmation. Import with one of these paths:

```text
Open the file with Pocket Casts from Files
Drag and drop the file onto the Simulator
Profile > Settings > Developer > Import Bundle
```

Use imports to reproduce user state locally, but keep exported databases and
logs out of the repository.

### Simulator Data

Find the installed app container:

```bash
xcrun simctl get_app_container <SIMULATOR_UDID> au.com.shiftyjelly.podcasts data
```

Prefer app export/import flows for sharing state. Directly editing simulator
containers is useful for local investigation, but it is easy to create state
that a user could not naturally reach.

### Crash Logs And Symbolication

Release artifacts include dSYMs inside the `xcarchive` file attached to GitHub
releases. Use the matching dSYM with a symbolication tool such as
MacSymbolicator when investigating crash logs.

Local Release builds upload dSYMs to Bitdrift only when `BITDRIFT_API_KEY` is
available. Debug and staging contributor builds can run without this key.

### Build Logs

For CLI builds, write logs to `/tmp` and keep `pipefail` enabled:

```bash
set -o pipefail
make build_staging 2>&1 | tee /tmp/pocketcasts-build.log
```

For the explicit simulator build flow, inspect:

```bash
/tmp/pocketcasts-sim-build.log
```

When a build fails, search from the bottom for the first meaningful compiler,
signing, package-resolution, or script-phase error. The final `xcodebuild`
summary is often less useful than the first failure above it.

### Common Setup Problems

If Bundler cannot find the expected Ruby, verify `rbenv`:

```bash
rbenv version
rbenv exec ruby --version
rbenv exec bundle --version
```

If `make build_staging` fails during credential generation, run:

```bash
make external_contributor
```

If tests cannot find a simulator, list installed simulators and pass a matching
OS:

```bash
xcrun simctl list devices available
make test_staging SIMULATOR_OS=18.5
```

If package resolution fails after switching branches:

```bash
xcodebuild -resolvePackageDependencies -project podcasts.xcodeproj -scheme "Pocket Casts Staging"
```

If static analysis fails in Semgrep, run the specific target in report-only mode
to inspect all findings, then fix the findings or update the relevant local rule
and fixture if the rule needs to change.

### Support Reproduction Checklist

When reproducing a support issue locally, capture the inputs that affect app
state before debugging:

1. App build, branch, and commit.
2. Simulator model and iOS runtime.
3. Account state, subscription state, and feature flags if relevant.
4. Import bundle or database export if the issue depends on user data.
5. Exact navigation path and whether the issue happens after force quit.
6. App logs and screenshots or screen recordings.

Keep user exports, logs, and recordings in a temporary local directory such as
`/tmp` or another private working folder, not in the repository checkout.

### Related Docs

- [localization.md](./localization.md) covers localization conventions and
  workflow.
- [Semgrep.md](./Semgrep.md) covers local Semgrep setup, rule files, and rule
  tests.
- [SecurityScanning.md](./SecurityScanning.md) summarizes the security scanning
  commands.
- [GitHubActionsLocalRunner.md](./GitHubActionsLocalRunner.md) covers local Mac
  runner setup for GitHub Actions.
