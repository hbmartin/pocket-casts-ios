<p align="center">
    <!-- Pocket Casts brand image -->
    <img alt="Pocket Casts" src="https://user-images.githubusercontent.com/308331/194037473-41ad7eba-8602-4be5-be73-49e3c0c48c12.svg#gh-light-mode-only" />
    <img alt="Pocket Casts" src="https://user-images.githubusercontent.com/308331/194041226-4c6d8181-cafa-4ea8-8735-1d8106f5e5f6.svg#gh-dark-mode-only" />
</p>

<p align="center">
    <!-- Badge: "Semgrep Swift Security: {trunk GitHub Actions status}" -->
    <a href="https://github.com/hbmartin/pocket-casts-ios/actions/workflows/semgrep.yml"><img alt="Semgrep Swift Security workflow status" src="https://github.com/hbmartin/pocket-casts-ios/actions/workflows/semgrep.yml/badge.svg?branch=trunk" /></a>
    <!-- Badge: "license: MPL" -->
    <a href="https://github.com/hbmartin/pocket-casts-ios/blob/trunk/LICENSE.md"><img alt="License MPL" src="https://img.shields.io/badge/license-MPL-black" /></a>
    <!-- Badge: "platform: ios|watchos" -->
    <img alt="Platform iOS and watchOS" src="https://img.shields.io/badge/platform-ios%20%7C%20watchos-lightgrey" />
    <!-- Badge: "Xcode: {version}+" -->
    <img alt="Xcode v26.4.1 or newer" src="https://img.shields.io/badge/Xcode-v26.4.1%2B-informational" />
</p>

<p align="center">
    Pocket Casts is the world's most powerful podcast platform, an app by listeners, for listeners.
</p>

## Setup

If you don't already have it, you need to install Bundler:

`gem install bundler`

Next you'll need to install all the dependencies needed for [_fastlane_](https://docs.fastlane.tools/) using this script:

`make install_dependencies`

## External contributors

If you're an external contributor run `make external_contributor`. After that you should be able to build and run the project.

## Swift Formatting

We use [SwiftLint](https://github.com/realm/SwiftLint) to ensure code is spaced and formatted the same way and follows the same [general conventions](https://github.com/Automattic/swiftlint-config). SwiftLint runs through the BuildTools Swift Package plugin, so no extra setup is required — just run it over the whole project with:

`make format`

You should do this before making a pull request.

## Running

Open the `.xcodeproj` file, select the Pocket Casts project and the Simulator Device you want to run on, and hit the play button.

## Building & Testing

The `make` targets wrap the common `xcodebuild` invocations:

```bash
make build_staging   # Build the "Pocket Casts Staging" scheme (StagingDebug)
make test_staging    # Build and run the unit tests
make static_checks   # SwiftLint, Semgrep rules/tests, and the Xcode static analyzer
make clean           # Clean the build artifacts
```

Scope the tests to a single class, method, or module with `ONLY_TESTING`:

```bash
make test_staging ONLY_TESTING=PocketCastsServerTests
make test_staging ONLY_TESTING=PocketCastsTests/YourTestClass/testMethodName
```

## Localization

You can learn more about localization at [docs/Localization.md](./docs/localization.md)

## Protocol Buffers

The app uses [Google Protocol Buffers](https://developers.google.com/protocol-buffers) to define our server objects.

To update server objects you'll need to install the protobuf command line tool as well as the [Swift Protobuf](https://github.com/apple/swift-protobuf) translators. This can be done via Homebrew with:

```
brew install protobuf
brew install swift-protobuf
```

To update the protobuf files you can then run:

Replace the `{API_PATH}` with the full path to the `pocketcasts-api/api/modules/protobuf/src/main/proto` folder

```
make update_proto API_PATH={API_PATH}
```

## Debugging

### Logs

Logs can be found in the app as a view and shared from there through the system sheet or mail:
* Profile > Help & Feedback > ⋯ > Logs

When debugging analytics, the `analyticsLogging` feature flag will enable logging for these events.

### Bitdrift

Pocket Casts uses [Bitdrift Capture](https://docs.bitdrift.io/sdk/quickstart) for crash and log collection. The SDK starts during app launch when `ApiCredentials.bitdriftSDKKey` has a value. External contributor builds leave this value empty, which skips Bitdrift startup.

To configure Bitdrift for internal builds, add the SDK key to the existing secrets JSON as:

```json
{
  "bitdrift_sdk_key": "..."
}
```

The credentials generator writes this into `podcasts/Credentials/ApiCredentials.swift` from `podcasts/Credentials/ApiCredentials.tpl`. Do not hard-code the SDK key in source files.

Release builds upload dSYMs to Bitdrift from the Xcode build phase `Upload Bitdrift Debug Files`. GitHub Actions release builds require `BITDRIFT_API_KEY` to be available in the runner environment; local Release builds without this variable skip the upload. The upload uses Bitdrift's [`bd debug-files upload`](https://docs.bitdrift.io/sdk/features/fatal-issues.html) command.

### Export Files

An export can be created with the database, settings plist, and logs for debugging purposes:
* Profile > Help & Feedback > ⋯ > Export Database - the export will include all log files and settings
* Profile > Settings > Developer > Export Bundle

These exports can also be imported to the app, replacing the database and settings with the ones from the file. This will prompt the user before replacement.
* Open the file with Pocket Casts directly from Files
* Drag and drop the file on the Simulator
* Profile > Settings > Developer > Import Bundle

### Crash Log Symbolication

All [releases](https://github.com/hbmartin/pocket-casts-ios/releases) include dSYMs inside of the `xcarchive` file.

These can be used along with the [MacSymbolicator](https://github.com/inket/MacSymbolicator) app to symbolicate any crash logs.
