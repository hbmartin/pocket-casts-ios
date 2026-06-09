## Formatting

Format all code using the formatter:
```bash
make format
```

## Static Checks

Run all local static checks with:
```bash
make static_checks
```

## Building and Running

```bash
make build_staging
```

## Cleaning Build Artifacts

```bash
make clean
```

## Running Tests

```bash
make test_staging
```

## Security Scanning

When PR feedback, unexpected planning decisions, bug discoveries, or other implementation learnings reveal a broader problem class that could be caught automatically, add or update local Semgrep rules in `semgrep/swift-security.yml`. Prefer rules that generalize the risk over rules that only freeze the exact fix already covered by tests. Do not add Semgrep rules for Ruby or Ruby-specific files.

### Running a Single Test

```bash
make test_staging ONLY_TESTING=PocketCastsTests/YourTestClass/testMethodName
```

### Running Module Tests

```bash
# DataModel module tests
make test_staging ONLY_TESTING=PocketCastsDataModelTests

# Server module tests
make test_staging ONLY_TESTING=PocketCastsServerTests

# Utils module tests
make test_staging ONLY_TESTING=PocketCastsUtilsTests
```

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
- Multi-platform targets: iOS, widgets, App Clip

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
make update_proto API_PATH=/path/to/pocketcasts-api/api/modules/protobuf/src/main/proto
```

## Simulator Launch Notes

When asked to get the app running in Simulator from the CLI, use an explicit simulator UDID instead of a generic destination to avoid Xcode choosing the wrong matching simulator/architecture.

If the build fails during credential generation because local secrets are missing, run:

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

Use `set -o pipefail` when piping through `tee`; otherwise a failed `xcodebuild` can look successful. After a successful build, install and launch the main app bundle:

```bash
xcrun simctl install <SIMULATOR_UDID> /tmp/pocketcasts-sim-deriveddata/Build/Products/StagingDebug-iphonesimulator/podcasts.app
xcrun simctl launch <SIMULATOR_UDID> au.com.shiftyjelly.podcasts
```
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
