## Task Runner

Tasks and tool versions (Ruby, semgrep) are managed by [mise](https://mise.jdx.dev) via `mise.toml`. One-time setup: `brew install mise && mise install`. List all tasks with `mise tasks`.

## Formatting

Format all code using the formatter:
```bash
mise run format
```

## Static Checks

Run all local static checks with:
```bash
mise run check:static
```

## Building and Running

```bash
mise run build:staging
```

## Cleaning Build Artifacts

```bash
mise run clean
```

## Running Tests

```bash
mise run test:staging
```

## Security Scanning

When PR feedback, unexpected planning decisions, bug discoveries, or other implementation learnings reveal a broader problem class that could be caught automatically, add or update local Semgrep rules in `semgrep/swift-security.yml`. Prefer rules that generalize the risk over rules that only freeze the exact fix already covered by tests. Do not add Semgrep rules for Ruby or Ruby-specific files.

### Running a Single Test

```bash
ONLY_TESTING=PocketCastsTests/YourTestClass/testMethodName mise run test:staging
```

### Running Module Tests

```bash
# DataModel module tests
ONLY_TESTING=PocketCastsDataModelTests mise run test:staging

# Server module tests
ONLY_TESTING=PocketCastsServerTests mise run test:staging

# Utils module tests
ONLY_TESTING=PocketCastsUtilsTests mise run test:staging
```

### UI Snapshot Tests

SwiftUI views are regression-tested with [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
in the `SnapshotTests` SwiftPM target (`Modules/Tests/SnapshotTests`). Image snapshots render through
`UIHostingController`, so they run on the iOS Simulator, not `swift test`.

```bash
# Verify against committed reference images
make test_staging ONLY_TESTING=SnapshotTests

# Record / refresh baselines, then review and commit the images under
# Modules/Tests/SnapshotTests/__Snapshots__/
SNAPSHOT_TESTING_RECORD=all make test_staging ONLY_TESTING=SnapshotTests
```

Record and verify on the Simulator/OS that CI pins (`IOS_SIMULATOR_RUNTIME_VERSION`); see
`docs/snapshot-testing.md` for the full workflow, the one-time Xcode scheme wiring required before CI
runs these, and how to extend snapshots to app-level themed views.

## Architecture

### Modular Structure

The codebase uses Swift Package Manager modules under `Modules/`:

- **DataModel** (`Modules/DataModel/`) - Core data persistence using GRDB. Contains podcast, episode, and playback models. Uses custom GRDB macros for model generation.
- **Server** (`Modules/Server/`) - API communication layer using Protocol Buffers. Depends on DataModel and Utils.
- **Utils** (`Modules/Utils/`) - Shared utilities including localization helpers.
- **DependencyInjection** (`Modules/DependencyInjection/`) - DI container for the app.

### Main App Structure

The main iOS app lives in `podcasts/` with:
- UIKit + SwiftUI hybrid (123+ ViewControllers, XIBs/Storyboards)
- Feature-based organization (Analytics, Bookmarks, Folders, IAP, Player, etc.)
- Multi-platform targets: iOS, widgets

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `podcasts/` | Main iOS app source |
| `PocketCastsTests/` | Unit tests organized by feature |
| `WidgetExtension/` | Home screen widgets |
| `BuildTools/` | SwiftLint and SwiftGen plugins |

## Data Access - DataManager (Singleton Facade)

All data operations go through `DataManager.sharedManager`:

```swift
// Located at: Modules/DataModel/Sources/PocketCastsDataModel/Public/DataManager.swift
let dataManager = DataManager.sharedManager

// Podcast operations
let podcasts = dataManager.allPodcasts(includeUnsubscribed: false)
let podcast = dataManager.findPodcast(uuid: "...")
dataManager.save(podcast: podcast)

// Episode operations
let episode = dataManager.findEpisode(uuid: "...")
dataManager.save(episode: episode)
let downloadedCount = dataManager.downloadedEpisodeCount()

// Playlist/Filter operations
let playlists = dataManager.allPlaylists(includeDeleted: false)
let episodes = dataManager.playlistEpisodes(for: playlist)

// Up Next queue
let queue = dataManager.allUpNextEpisodes()

// Folder operations
let folders = dataManager.allFolders(includeDeleted: false)
let podcastsInFolder = dataManager.allPodcastsInFolder(folder: folder)
```

## Localization

Strings are managed via SwiftGen. Add new strings to `podcasts/en.lproj/Localizable.strings`:

```swift
/* Description for translators with placeholder info */
"feature_description_key" = "Value with %1$@ placeholder";
```

Use generated `L10n` enum:
```swift
let text = L10n.featureDescriptionKey(value)
```

Key rules:
- Use snake_case keys with pattern: `feature_relevantIdentifier_description`
- Always include comment describing context and placeholders
- Use positional specifiers (`%1$@`, `%2$@`), never string interpolation
- Handle plurals manually with separate `_singular`/`_plural` keys

## Code Style

SwiftLint is configured with opt-in rules. Notable custom rules:
- Use `naturalContentHorizontalAlignment` instead of `.left`/`.right` for RTL support
- Use `.natural` text alignment instead of `.left`
- Never use `LocalizedStringKey` in SwiftUI - use `NSLocalizedString` with L10n

## Themes
- When styling Views, use `@EnvironmentObject private var theme: Theme` and inject `.environmentObject(Theme.sharedTheme)` where the View is used.
- Use `AppTheme.color(for: .primaryText01, theme: theme)` to access themed colors

## Protocol Buffers

Server objects use protobuf. To regenerate after API changes:

```bash
brew install protobuf swift-protobuf  # One-time setup
mise run generate:proto /path/to/pocketcasts-api/api/modules/protobuf/src/main/proto
```

## Simulator Launch Notes

When asked to get the app running in Simulator from the CLI, use an explicit simulator UDID instead of a generic destination to avoid Xcode choosing the wrong matching simulator/architecture.

If the build fails during credential generation because local secrets are missing, run:

```bash
mise run setup:credentials
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

Use `set -o pipefail` when piping through `tee`; otherwise a failed `xcodebuild` can look successful. After a successful build, install and launch the main app bundle:

```bash
xcrun simctl install <SIMULATOR_UDID> /tmp/pocketcasts-sim-deriveddata/Build/Products/StagingDebug-iphonesimulator/podcasts.app
xcrun simctl launch <SIMULATOR_UDID> au.com.shiftyjelly.podcasts
```
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
