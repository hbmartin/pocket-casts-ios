# Swift 6.3 + iOS 26 Full Migration Plan — Pocket Casts iOS

## Context

The user asked for a plan to migrate to Swift 6.3 and "fully migrate to take advantage of iOS 26", accompanied by a generic migration guide. Exploration showed this repo is far ahead of the guide's assumptions, so most of the guide's big-ticket items **do not apply**:

- Xcode is pinned to **26.4.1** (`.xcode-version`) — the Swift 6.3 compiler is already in use. `config/PocketCasts.base.xcconfig` sets `SWIFT_VERSION = 6.0` (language mode — 6.0 IS the latest mode) with `SWIFT_STRICT_CONCURRENCY = complete` and an **empty** warning baseline (`scripts/ci/concurrency-baseline.txt`). The app target already adopted `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY = YES` (MODERNIZATION.md, 2026-07-05).
- **UIScene lifecycle fully adopted** (`podcasts/SceneDelegate.swift`); no StoreKit 1 (subscriptions are server-side, only `AppStore.requestReview` used); no CLGeocoder; GRDB persistence (no Core Data). SPM-only, no CocoaPods/Carthage. No watch/App Clip/CarPlay targets.
- Liquid Glass adoption is already in progress behind `FeatureFlag.liquidGlass` (default true) with ~21 `#available(iOS 26)` guards and central gate `podcasts/LiquidGlass.swift`.
- Nightly CI already runs the unit suite on the iOS 26.5 runtime.

**What actually remains** (the real migration): deployment target is iOS 18.6 (40 pbxproj configs) / Modules at `.iOS("18.0")`; both `Package.swift` at tools 6.0; ~193 string-based `NotificationCenter` observers across ~84 files; tests ~99% XCTest; two legacy `UIWindow(frame:)` sites; docs lag the code.

**User decisions (locked via AskUserQuestion):**
1. **Raise minimum deployment target to iOS 26.0** everywhere; delete all availability guards and pre-26 code paths; retire `FeatureFlag.liquidGlass`.
2. **Full sweep** migration to iOS 26 typed `NotificationCenter` messages (all ~84 files, ~91 names).
3. **Migrate the SPM module test targets to Swift Testing** (app-target `PocketCastsTests` and `SnapshotTests` stay XCTest).

Every phase is a landable PR that keeps the build green. **Per-phase verification gate:** `mise run build:staging`, `mise run test:staging`, `mise run check:static`, `mise run check:concurrency` (baseline must stay empty).

---

## Phase 0 — CI runway: promote iOS 26 runtime (min target still 18.6)

Front-load runtime risk before any product change. Nightly matrix is already green on 26.5.

1. GitHub repo variable `IOS_SIMULATOR_RUNTIME_VERSION` → `26.5` (admin action, read at `.github/workflows/ios-ci.yml:25`). Self-hosted runners already have the 26.5 runtime (nightly proves it).
2. `.github/workflows/nightly-runtime-checks.yml`: TSan `RUNTIME_VERSION: "18.6"` → `"26.5"` (~line 29), UI smoke `"18.6"` → `"26.5"` (~line 83), update job display names. The now-redundant `runtime_matrix` `["26.5"]` entry: repoint at a newer beta runtime or leave.
3. `mise.toml`: change `SIMULATOR_OS:-18.6` defaults → `26.5` in `test`, `test:staging`, `test:tsan`, `test:smoke-ui`, `smoke:launch`.
4. **Snapshot re-record #1** on the 26.5 simulator (`SNAPSHOT_TESTING_RECORD=all`, per `docs/snapshot-testing.md`) — iOS 26 rendering will likely shift anti-aliasing past the perceptual tolerance. Review diffs, commit `Modules/Tests/SnapshotTests/__Snapshots__/`.
5. Update `docs/snapshot-testing.md` pinned-runtime guidance.

## Phase 1 — Deployment-target bump to iOS 26.0 (single PR)

Move the setting to the shared xcconfig (verified feasible: all 4 project-level configurations base on `config/PocketCasts.{debug,staging,prototype,release}.xcconfig`, which include `PocketCasts.base.xcconfig`; pbxproj buildSettings are the only overrides and we delete them).

1. `config/PocketCasts.base.xcconfig`: add `IPHONEOS_DEPLOYMENT_TARGET = 26.0` with a comment in the file's style.
2. `podcasts.xcodeproj/project.pbxproj`: delete all 40 identical `IPHONEOS_DEPLOYMENT_TARGET = 18.6;` lines (`sed -i '/IPHONEOS_DEPLOYMENT_TARGET = 18.6;/d'`). Verify: `grep -c` in pbxproj → 0, and `xcodebuild -showBuildSettings -scheme "Pocket Casts Staging" | grep IPHONEOS` → 26.0.
3. `Modules/Package.swift`: platforms `.iOS("18.0")` → `.iOS("26.0")`; **keep** `.macOS(.v10_15)` (GRDBMacros plugin / `swift build` host tooling need it).
4. Leave `#available(iOS 26)` guards alone in this PR (always-true compiles fine; deletion is Phase 2).
5. Build once, fix any xib/storyboard "targets earlier iOS version" IB warnings by batch-updating their `deployment` metadata.
6. Manual smoke on iOS 26 sim: app + all 6 extensions (widget gallery, share sheet, notification content, Siri intents).
7. Tag the last 18.6-compatible build before merging (re-release ability for sub-26 users).

## Phase 2 — Retire `FeatureFlag.liquidGlass`, delete pre-26 paths (2 PRs)

**PR 2a — flag + guard retirement (semantic no-op):**
1. `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`: delete `case liquidGlass` (line ~208) and its `enabled` arm. Follow `docs/FeatureFlagAudit.md` removal process (remote-key sign-off for `liquid_glass`, record in audit table like the 2026-06-27 removals).
2. `podcasts/LiquidGlass.swift`: `LiquidGlass.isEnabled` → `static let isEnabled = true` temporarily.
3. Delete all 21 `#available(iOS 26.0, *)` guards across 11 files (`LiquidGlass.swift`, `Main/MainTabBarController.swift` + `+Animations.swift`, `MiniPlayerViewController.swift` + `+Positioning/+TransitionDelegate`, `PlayerContainerViewController+Gestures.swift`, `Extensions/UIViewController+TabBar.swift`, `MultiSelectFooterView.swift`, `TranscriptSearchAccessoryView.swift`, `Up Next History/UpNextEntryView.swift`) — inline the true branch, delete fallbacks. Also the one legacy `#available(iOS 10` check.

**PR 2b — dead-branch sweep:**
1. Inline `LiquidGlass.isEnabled` at all ~59 call sites (~40 files), deleting every legacy `else` branch: `MainTabBarController`(+Animations), `PCNavigationController.swift`, `LargeNavBarViewController.swift`, mini-player stack, `PlayerTabsView.swift`, `PCSearchBarController.swift`, etc.
2. Delete the `LiquidGlass` enum; simplify `Constants.effectiveMiniPlayerOffset` (→ `0`) and `effectiveFooterViewPadding` (→ offset + 4) in `podcasts/LiquidGlass.swift`, then consider inlining; keep `applyInterfaceStyleForActiveTheme()` minus its guard.
3. Replace the two legacy windows: `podcasts/Utilities/SceneHelper.swift:17` (fallback — delete or assert; likely unreachable) and `podcasts/Common Components/Feature Tour/FeatureTour.swift:20` → `UIWindow(windowScene:)` (take the scene from the presenting view's window).
4. Heavy manual QA of chrome (tab bar, `UITabAccessory` mini player, nav bars, search), light/dark, iPad. Snapshot re-record only if an EndOfYear view changed (unlikely).

## Phase 3 — Swift 6.3 tooling & language features (1–2 PRs)

1. `Modules/Package.swift` + `BuildTools/Package.swift`: `// swift-tools-version: 6.3`. Keep explicit `.swiftLanguageMode(.v6)` per target. Confirm SwiftLintPlugins 0.63.3 / SwiftGenPlugin 6.6.2 resolve under 6.3.
2. **Default isolation** (`.defaultIsolation(MainActor.self)`):
   - **Adopt for `EndOfYear`** (pure SwiftUI; aligns with app target). Expect a round of `nonisolated` annotations; heed MODERNIZATION.md gotchas (isolated synthesized deinit crash swiftlang/swift#87316 → `nonisolated deinit {}` workaround; extensions need own `nonisolated`).
   - **Not** for `PocketCastsUtils`/`DataModel`/`Server`/`GRDBMacros` (deliberately off-main layers) nor app extensions (existing documented decision). Document rationale.
3. **Upcoming features:**
   - `NonisolatedNonsendingByDefault`: **adopt** in SPM module targets (add to `strictConcurrencySettings`) to align with the app target's `SWIFT_APPROACHABLE_CONCURRENCY = YES` — removes cross-module async-semantics mismatch. Mechanize with `swift package migrate --to-feature NonisolatedNonsendingByDefault`, hand-review `@concurrent` insertions (Server URLSession paths); run `PocketCastsServerTests` + local `mise run test:tsan`.
   - `ExistentialAny`: **defer** (syntactic churn, no runtime value). Document.
4. **`@preconcurrency` audit** (one PR): for each of the 28 files in `podcasts/` (8 `+Swipe.swift` SwipeCellKit files, `AppDelegate.swift`, `DownloadManager.swift`, `DefaultPlayer.swift`, `MediaExporter.swift`, `Utilities/NotificationsHelper.swift`, `SiriSettingsViewController.swift`, …) remove the attribute, rebuild, keep only where diagnostics return (iOS 26 SDK annotations should clean up many UserNotifications/Intents/AVFoundation imports; the SwipeCellKit fork likely still needs it). PR description carries kept/removed table.

## Phase 4 — Typed NotificationCenter: infrastructure + spike (1 PR)

Key property: a message type implementing `name`/`makeMessage(_:)`/`makeNotification(_:)` **bridges bidirectionally** with string-based posts/observers on the same `Notification.Name` — posters and observers migrate independently, green at every commit.

Design (verified against current code):
- **All messages are `NotificationCenter.MainActorMessage`** — every custom post already funnels through `NotificationCenter.postOnMainThread` (`Modules/Sources/PocketCastsUtils/Extensions/NSNotificationCenterExtension.swift`, `DispatchQueue.main.sync`), and observers are overwhelmingly UI. No `AsyncMessage` during the sweep (would change delivery ordering).
- **Naming**: one struct per notification, past-tense, no suffix — `EpisodePlayStatusChanged`, `PlaybackStarted`, `UpNextEpisodeAdded(episodeUuid:addedToTop:)`. `object as? String` uuid → typed `episodeUuid` property; `userInfo` keys → properties.
- **Location**: new `podcasts/Notifications/` — one file per domain (`PlaybackMessages.swift`, `EpisodeMessages.swift`, `UpNextMessages.swift`, `PodcastMessages.swift`, `UIMessages.swift`, `AccountMessages.swift`). Server: public message structs in `Modules/Sources/PocketCastsServer/Public/ServerNotifications.swift` (cross-module works — shared `NotificationCenter.default` + bridged raw names).
- **Bridged representation frozen during the sweep**: `makeNotification` keeps uuid in `object`, extras under today's userInfo keys, so unconverted observers keep working.
- **Boilerplate reducer** for the ~30 uuid-in-object names: `protocol UuidBridgedMessage: NotificationCenter.MainActorMessage` with default `makeMessage`/`makeNotification`.
- **Posting helper** in `NSNotificationCenterExtension.swift` preserving blocking main-sync semantics: `static func postOnMainThread<M: NotificationCenter.MainActorMessage>(_ message: M)` (`Thread.isMainThread ? MainActor.assumeIsolated { post } : DispatchQueue.main.sync { post }`).
- **Token lifecycle**: extend the two existing observer bags — `podcasts/SimpleNotificationsViewController.swift` (base of `PCViewController`) and `podcasts/Utilities/CustomObserver.swift` — with `private var messageTokens: [NotificationCenter.ObservationToken]` and `func addCustomObserver<M: NotificationCenter.MainActorMessage>(_ type: M.Type, handler: @escaping (M) -> Void)` (keep the existing dedupe-by-name behavior); `removeAllCustomObservers()` also removes tokens. Preserves the register-in-`viewWillAppear`/remove-in-`viewWillDisappear` idiom, so per-VC diffs stay local. Non-bag sites (`EpisodeCell` deinit-based, block observers) store tokens in a property and remove where `removeObserver` happens today — always remove explicitly.
- **System notifications**: adopt Apple's iOS 26 typed messages where they exist (keyboard, etc. — the spike inventories the 26.4 SDK); keep legacy `addObserver` where none exists (AVAudioSession, AVPlayerItem). Mixed usage per file is fine.
- **SwiftUI observers**: inventory `publisher(for:)`/`.onReceive` in the spike; convert to `for await` over typed sequences or defer to Phase 6.

**Spike deliverable** (proves SDK API shapes before the sweep): infrastructure + one real message end-to-end — `EpisodePlayStatusChanged`, posted at `podcasts/EpisodeManager.swift:36,148`, all ~12 observer sites converted (`EpisodeCell.swift:165`, `PodcastViewController.swift:493`, `ListeningHistoryViewController.swift:114`, `StarredViewController.swift:149`, `UploadedViewController.swift:170`, `PodcastListViewController.swift:140`, `EpisodeDetailViewController.swift:274`, `UserEpisodeDetailViewController.swift:169`, `PlaylistDetailViewController+Observers.swift:20`, `PlaylistCacheInvalidationCoordinator.swift:51`, `ShortcutManager.swift:19`, `BadgeHelper.swift:17`), then delete the constant.

## Phase 5 — Typed NotificationCenter: domain sweeps (6 PRs)

Per-file checklist: replace `addObserver`/selector with typed handler (inline the `@objc` body, delete `object`/`userInfo` casts) → replace posts with `postOnMainThread(Message(...))` → confirm no `object:`-filtered registrations regress (current sites all pass `object: nil`) → delete unused `@objc` funcs → delete each `Notification.Name` constant when it hits zero refs → run the verification gate.

Order (heaviest shared observers land with their domain):
- **5.1 Episode status** (~9 names): finishes `EpisodeCell.swift` (18 observers — riskiest file, done early), `EpisodeManager.swift` posts.
- **5.2 Playback** (~15 names): `PlaybackManager.swift` (12 observers), `DefaultPlayer.swift`, player VC stack, `MiniPlayerViewController`.
- **5.3 Up Next** (4 names incl. `upNextEpisodeAdded` with `addedToTop` payload from `PlaybackQueue.swift:105` → `MainTabBarController+Animations.swift:22`): `UpNextViewController.swift` (13), `MainTabBarController.swift` (12).
- **5.4 Podcast/folder/filter/discover** (~15 names).
- **5.5 Server module** (17 `ServerNotifications` + `serverUserWillBeSignedOut`): posts in `ServerNotificationsHelper.swift`, refresh/API tasks, `UploadManager.swift`; app-side observers (`WidgetHelper.swift` (9), `BadgeHelper`, profile/sync UI). Server is nonisolated-by-default — posts go through the typed `postOnMainThread` helper.
- **5.6 UI chrome + account** (theme, textEditing, tab taps, mini-player appear/disappear, `podcasts/Notifications.swift`, locals in `ShareProfileViewModel.swift`/`PodcastFeedViewModel.swift`) + system-notification typed adoption where the SDK provides messages.

## Phase 6 — Typed-notification cleanup (1 PR)

- Delete `Constants.Notifications` from `podcasts/Constants.swift`, `podcasts/Notifications.swift`, and the `NSNotification.Name` constants in `ServerNotifications.swift` (raw strings live inside message types; never change them — effectively ABI).
- Delete selector-based `addCustomObserver(_:selector:)` from both bags and legacy `postOnMainThread(notification:object:userInfo:)` once grep shows zero refs.
- Add a grep ratchet to `scripts/ci/static-checks.sh`: fail on new `addObserver(self, selector:` / `postOnMainThread(notification:` outside an allowlist of remaining system-notification sites.

## Phase 7 — Swift Testing for SPM module tests (4 PRs, one per target)

Scope: `PocketCastsUtilsTests` (17 files, pilot exists: `ReloadSchedulerTests.swift`), `PocketCastsDataModelTests` (33), `PocketCastsServerTests` (18), `GRDBMacrosTests`+`ModulesTests` (1 each, fold in). `SnapshotTests` + app `PocketCastsTests` stay XCTest (snapshot tooling and `check-snapshot-coverage.rb` parse XCTest xcresults). XCTest/Swift Testing coexist per target → migrate file-by-file; no `UnitTests.xctestplan` changes.

Mechanics per file:
- `XCTestCase` class → `struct` by default; `final class` + `deinit` only when teardown must run on failure. `setUp`/`tearDown` → `init`/`deinit` or local fixtures (prefer a temp-GRDB-DB helper with deinit/`defer` cleanup for DataModel).
- `XCTAssert*` → `#expect`; `XCTUnwrap` → `try #require`; `XCTFail` → `Issue.record`.
- The 3 files using `XCTestExpectation` (2 Utils, 1 Server) → `await confirmation {}` or plain `await`.
- **Parallelism is the top flake risk** (Swift Testing is parallel by default): suites touching shared singletons (`UserDefaults`, `Settings`, shared DB paths) get `.serialized` initially; relax later.
- `@MainActor` on suites exercising MainActor types (as in the pilot); audit whether product-code `nonisolated deinit {}` workarounds become deletable as files leave XCTest.
- Parameterize table-shaped DataModel tests with `@Test(arguments:)`. `GRDBMacrosTests`: swift-macro-testing's `assertMacro` works under Swift Testing.
- Verify per PR: `mise run test:staging ONLY_TESTING=<target>`, plus 3 consecutive CI runs to catch parallelism flakes.

## Phase 8 — Documentation (final PR)

- `MODERNIZATION.md`: iOS 26 floor, typed notifications, Swift Testing, tools 6.3, isolation decisions (EndOfYear adopted; DataModel/Server/extensions deliberately not; ExistentialAny deferred).
- New `docs/ModernizationSummary-2026-07.md`; `docs/FeatureFlagAudit.md` liquidGlass row → removed; `docs/GettingStarted.md` requirements; finish `docs/snapshot-testing.md`.

---

## Risks / unknowns

- **Typed NotificationCenter SDK exactness** (Subject typing, `ObservationToken` semantics, which UIKit messages ship in 26.4): mitigated by the Phase 4 spike — nothing sweeps until one message is proven end-to-end.
- **Delivery-semantics drift**: keep the blocking main-sync post helper; all messages `MainActorMessage`; no `AsyncMessage` during the sweep.
- **Dependency floors**: Kingfisher/SwipeCellKit-fork/JLRoutes/GRDB 7 all have floors far below 26 — SPM builds at `max(floor, platform)`, no breakage expected; watch JLRoutes (old ObjC) deprecation warnings under the 26 SDK.
- **Sub-26 users dropped**: locked decision; tag the last 18.6 build, note in release/support docs.
- **Snapshot churn**: two re-record events (Phase 0 runtime, possibly Phase 2 chrome) — review diffs, never blind-commit.
- **Concurrency ratchet must stay empty**: deleting `else` branches / converting selectors to closures can surface isolation warnings — `mise run check:concurrency` every PR.
- **`NonisolatedNonsendingByDefault` in Server** changes where nonisolated async funcs run (caller's executor): re-test URLSession bridges (unit + nightly TSan).
- **Widget/extension rendering on iOS 26**: visual QA after Phase 1 (Liquid Glass widget treatment, share sheet, notification content).
- **CI admin dependency**: `IOS_SIMULATOR_RUNTIME_VERSION` repo variable change is outside any PR; runners need the 26.5 runtime (nightly suggests they have it).
- **Isolated-deinit crash (swiftlang/swift#87316)** resurfaces in the `@preconcurrency` audit and Swift Testing conversion; in-repo `nonisolated deinit {}` workaround pattern applies.

## Key existing utilities to reuse

- `NotificationCenter.postOnMainThread` — `Modules/Sources/PocketCastsUtils/Extensions/NSNotificationCenterExtension.swift` (extend with typed overload)
- Observer bags: `podcasts/SimpleNotificationsViewController.swift`, `podcasts/Utilities/CustomObserver.swift` (extend with token-based overload)
- Concurrency ratchet: `scripts/ci/check-concurrency-warnings.sh` + `mise run check:concurrency` / `concurrency:baseline`
- Feature-flag removal process: `docs/FeatureFlagAudit.md` (2026-06-27 removals as template)
- Swift Testing pilot: `Modules/Tests/PocketCastsUtilsTests/ReloadSchedulerTests.swift`
- Snapshot workflow: `docs/snapshot-testing.md`

## Verification (end-to-end)

Per phase: `mise run build:staging` + `mise run test:staging` + `mise run check:static` + `mise run check:concurrency` (empty baseline). Snapshot phases: `SNAPSHOT_TESTING_RECORD=all` re-record then verify run. Phase 3 Server changes: `mise run test:tsan` locally + one nightly TSan pass. Phases 1–2: manual smoke on iOS 26 simulator covering app chrome (tab bar, mini player via `UITabAccessory`, nav bars, search, light/dark, iPad) and all 6 extensions. Phase 5: after each domain PR, exercise the domain's flows in the simulator (play/pause/archive/star for 5.1–5.2, Up Next add/remove for 5.3, sync/sign-out for 5.5). Phase 7: 3 consecutive green CI runs per converted target.