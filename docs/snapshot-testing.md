# UI Snapshot Testing

We use [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
to guard SwiftUI views against unintended visual changes. A snapshot test renders a view, compares
it pixel-by-pixel against a committed reference image, and fails on any difference — catching theme,
layout, and Dynamic Type regressions that view-model unit tests cannot.

This document covers the pilot setup, the recording workflow, and how to extend coverage.

## What is set up

- **Dependency**: `swift-snapshot-testing` is declared explicitly in `Modules/Package.swift`. It was
  already resolved transitively (via `swift-macro-testing`, which powers the GRDB macro tests), so
  no new package is fetched — the declaration just exposes the `SnapshotTesting` product to test
  targets.
- **Target**: a `SnapshotTests` SwiftPM test target (`Modules/Tests/SnapshotTests`) depending on
  `EndOfYear` and `SnapshotTesting`.
- **Helper**: `assertThemedSnapshots(...)` renders a view across a matrix of appearance
  (`light`/`dark`) and Dynamic Type sizes, writing one suffixed reference image per combination.
- **Pilot**: `CircularProgressViewSnapshotTests` snapshots the real `EndOfYear/CircularProgressView`
  — a deterministic, dependency-light view — in light and dark.
- **Reference images**: live in `Modules/Tests/SnapshotTests/__Snapshots__/` and are excluded from
  the SwiftPM target so they are not treated as build resources.

## Where snapshots run

Image snapshots render through `UIHostingController`, which requires UIKit, so **they must run on an
iOS Simulator** — not via `swift test` on the macOS host (that builds for macOS and the image
strategy is unavailable). The helper file is wrapped in `#if canImport(UIKit)` for that reason.

Determinism matters: reference images are sensitive to the renderer. Record and verify on the **same
Simulator/OS** that CI pins via the `IOS_SIMULATOR_RUNTIME_VERSION` variable, and on the pinned Xcode
(`.xcode-version`). Images recorded on a different device or OS will produce false failures. The
helper applies a small `perceptualPrecision` tolerance (0.98) to absorb sub-pixel anti-aliasing
differences; tune it per view if a snapshot proves flaky.

## Recording / refreshing baselines

Recording is controlled by swift-snapshot-testing's standard `SNAPSHOT_TESTING_RECORD` environment
variable (the same mechanism the GRDB macro tests already use). Set it to `all` to (re)write every
reference image, then **review the image diff and commit the results**:

```bash
SNAPSHOT_TESTING_RECORD=all xcodebuild test \
  -project podcasts.xcodeproj \
  -scheme "Pocket Casts Staging" \
  -configuration StagingDebug \
  -only-testing:SnapshotTests \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

To verify (the default, no env var), drop `SNAPSHOT_TESTING_RECORD`. On the very first run there are
no references, so the assertions record them and fail; commit the images and re-run to get green.

> Review norm: a snapshot test only has value if the recorded image is actually inspected. When a PR
> changes reference images, review them like code — confirm the visual change is intended. Do not
> blanket-re-record to make red tests pass.

## Repository hygiene

Reference images are binary and live forever in history, so be deliberate:

- Snapshot **stable, high-value** views; avoid animation-driven or network/image-loading views whose
  output is non-deterministic.
- Keep the trait matrix small. Only add Dynamic Type sizes for views with text (purely geometric
  views render identically across content size categories, so extra baselines are pure waste).
- Prefer `.fixed`/`.sizeThatFits` layouts over full-device snapshots unless device chrome matters.
- For non-visual output (formatted strings, accessibility trees, model dumps), prefer **textual or
  inline** snapshots (`InlineSnapshotTesting`, also vendored via swift-macro-testing) — no binaries.

## Running in CI (one-time Xcode wiring)

`SnapshotTests` is a SwiftPM test target and is not yet part of any Xcode scheme's Test action, so
`-only-testing:SnapshotTests` will not find it until it is added. In Xcode, edit the **Pocket Casts
Staging** scheme → Test → add the `SnapshotTests` target (or add it to `PocketCastsTests/UnitTests.xctestplan`).
This step is intentionally left to be done in the IDE so the project file is updated by Xcode rather
than hand-edited. Once wired, CI can run it via `make test_staging ONLY_TESTING=SnapshotTests`.

## Extending to app-level themed views

The pilot lives in a SwiftPM module, so it can only reach views defined in `Modules/`. The app's
~9 custom themes (`light, dark, extraDark, electric, classic, indigo, rosé, contrastLight,
contrastDark`) and most screens live in the `podcasts` app target and are reachable only from
`PocketCastsTests`.

To snapshot those:

1. In Xcode, add the `SnapshotTesting` package product to the **PocketCastsTests** target
   (Target → General → Frameworks, or the project's Package Dependencies). `PocketCastsTests` does
   not currently link any SwiftPM product, so this adds its first `packageProductDependencies` entry
   — do it through Xcode rather than editing `project.pbxproj` by hand.
2. Add a themed helper alongside the app tests that injects the app `Theme` and loops the real theme
   cases, e.g. render the view inside `.environmentObject(Theme(previewTheme: themeType))` and snapshot
   per case. This is the app-target analogue of `assertThemedSnapshots`, which only varies the
   system `userInterfaceStyle`.

## Note on `Package.resolved`

The committed lockfile previously pre-dated the `swift-macro-testing` adoption and was missing its
transitive pins. Those pins (`swift-snapshot-testing`, `swift-custom-dump`, `swift-macro-testing`,
`xctest-dynamic-overlay`) are now present. The file's `originHash` is finalized by SwiftPM on the
next `swift package resolve` / Xcode build on macOS; resolution is not frozen in CI, so this happens
automatically and changes no resolved versions.
