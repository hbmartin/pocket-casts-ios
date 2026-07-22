# Pocket Casts iOS — Local-First & Product Modernization Program

**Plan date:** 2026-07-12 · **Branch:** `claude/project-improvement-ideas-hhdzq0` · **Repo:** hbmartin/pocket-casts-ios

## Context

A repo-wide survey (2026-07-12) produced 68 improvement ideas spanning local-first architecture, player features, on-device intelligence, testing/CI, and tech-debt cleanup. The user reviewed every idea individually and rendered a decision on each. This plan is the authoritative record of those decisions and the implementation blueprint for the accepted work.

The fork's strategic direction this program serves: **a local-first Pocket Casts** — fully functional with no account (on-device RSS refresh, local storage, file-based device sync), with server sync as an optional layer when signed in — plus a round of user-facing player features and a testing/CI hardening pass. The Swift 6 / strict-concurrency / DI-seam modernization (MODERNIZATION.md phases 0–5) is complete and is the foundation this builds on.

**Explicit user requirements for this plan:**
1. Capture EVERY decision from the user's 68-item review in this plan file itself (see Decision Register).
2. Be extremely thorough — this file doubles as documentation/backup/reference.
3. Include technical details and file names.

---

## Decision Register (authoritative)

User decisions given 2026-07-12, item-by-item against the 68-idea survey. Dispositions: **DO** = implement in this program · **DEFER** = do not implement now; record thoroughly in `docs/DeferredWork.md` (new) · **SKIP/NO** = do not implement; recorded here only · **DELETE** = remove existing artifact.

| #    | Idea                                                         | Decision                                                     |
| ---- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 1    | Ship FileSync                                                | **DO** — remove the gate entirely (`FeatureFlag.fileSync` deleted; feature available in all builds) |
| 2    | On-device feed refresh automation                            | **DO** — automatic local refresh **when no account is signed in** |
| 3    | Raw-SQL → GRDB query interface conversion                    | **DO** — complete it; retire `grdbQueryInterface` flag       |
| 4    | Typed-NotificationCenter migration                           | **DO** — execute the existing plan (phases 4–6 of `docs/Swift 6.3 + iOS 26 Full Migration Plan — Pocket Casts iOS.md`) |
| 5    | Retire stale feature flags                                   | **DO** — user asked to review the candidate list; follow-up answers: retire **only the 32 simple candidates** (leave the 9 wide-adoption candidates for a later pass) AND **retire all 17 playback-adjacent flags** (deferral rationale expired when playback modernization completed 2026-07-05) |
| 6    | Storage: local always, sync optional                         | **DO** — migrate storage so the app is fully local-capable always, syncing only when signed in. Un-gate `generatedChapters`, `upNextSort`, `shareProfile`, `voiceBoostN` (fully available). Follow-up answer: **server refresh remains the pipeline when signed in**; local refresh is automatic when signed out |
| 7    | DI call-site conversion (~446 `DataManager.sharedManager` etc.) | **DEFER** — write to repo doc                                |
| 8    | VC splits (`PlaybackManager` 2,638 lines, `PodcastViewController` 1,738, `Settings` 1,608, `TranscriptViewController` 1,372) | **DEFER** — write to repo doc                                |
| 9    | Swift Testing migration (XCTest → `@Test`)                   | **DEFER** — write to repo doc                                |
| 10   | Document audio fingerprinting                                | **DO** — thorough documentation in its own file              |
| 11   | Loudness normalization (EBU R128)                            | **DO**                                                       |
| 12   | Now Playing Live Activity + Dynamic Island                   | **DO**                                                       |
| 13   | Chapter-aware smart skip                                     | **DO**                                                       |
| 14   | Adaptive effects switching (music/speech auto-profiles)      | **DEFER** — write to repo doc                                |
| 15   | Expand Control Center controls (iOS 26)                      | **DO**                                                       |
| 16   | Sleep timer polish (fade-out, shake-to-extend)               | **SKIP**                                                     |
| 17   | Route-aware playback rules                                   | **DO**                                                       |
| 18   | On-device transcription (`SpeechAnalyzer`)                   | **DEFER** — write to repo doc                                |
| 19   | FoundationModels episode intelligence                        | **DEFER** — write to repo doc                                |
| 20   | Semantic library search                                      | **DESIGN DOC ONLY** (follow-up answer) — thorough standalone `docs/SemanticSearch.md`; implementation deferred |
| 21   | Transcript reader mode                                       | **DO — all parts** (reader view, follow-along highlighting, in-transcript search, quote-share via clip exporter) |
| 22   | Rewind-based bookmark suggestions                            | **SKIP**                                                     |
| 23   | Local "Year in Pods" recap                                   | **SKIP**                                                     |
| 24   | `ObservableObject` → `@Observable` migration                 | **DEFER** — write to repo doc                                |
| 25   | Consolidate SiriKit onto App Intents                         | **DO**                                                       |
| 26   | Adopt GRDB `ValueObservation`                                | **DO**                                                       |
| 27   | MetricKit ingestion                                          | **DO**                                                       |
| 28   | TipKit feature discovery                                     | **DO**                                                       |
| 29   | SharePlay listening sessions                                 | **DEFER** — write to repo doc                                |
| 30   | CarPlay                                                      | **NO**                                                       |
| 31   | SnapshotTests + GRDBMacrosTests in CI                        | **DO**                                                       |
| 32   | Per-PR UI smoke subset                                       | **SKIP**                                                     |
| 33   | Coverage floor raise + coverage upload                       | **DEFER** — write to repo doc                                |
| 34   | Use the themed snapshot helper broadly                       | **DO**                                                       |
| 35   | Tests for untested features (Player/Onboarding/Settings VCs/Sharing) | **DEFER** — write to repo doc                                |
| 36   | Property-test & fuzz the FeedParser                          | **DO**                                                       |
| 37   | Simulation-test the FileSync merge engine                    | **DO**                                                       |
| 38   | Mutation testing on strong suites                            | **DO**                                                       |
| 39   | Performance regression tests (XCTMetric baselines)           | **DEFER** — write to repo doc                                |
| 40   | Accessibility audits in tests                                | **SKIP**                                                     |
| 41   | Linux `swift test` for SPM modules                           | **SKIP**                                                     |
| 42   | GitHub merge queue                                           | **SKIP**                                                     |
| 43   | Binary size tracking                                         | **SKIP**                                                     |
| 44   | Surface build-time trends                                    | **DO**                                                       |
| 45   | Automated dependency updates (Renovate/osv-scanner/SBOM)     | **DEFER** — write to repo doc                                |
| 46   | Expanded nightly runtime matrix                              | **SKIP**                                                     |
| 47   | Pre-commit mise task + hooks                                 | **SKIP**                                                     |
| 48   | Extra Danger rules                                           | **SKIP**                                                     |
| 49   | Organize flat root of `podcasts/` (367 flat files)           | **DEFER** — write to repo doc                                |
| 50   | Extract features into SPM modules                            | **DEFER** — write to repo doc                                |
| 51   | Activate the `@unchecked Sendable` gate                      | **DO**                                                       |
| 52   | `as!` force-cast burndown                                    | **SKIP**                                                     |
| 53   | Retire last Objective-C; port MNAVChapterReader              | **DO**                                                       |
| 54   | Modernize theme codegen                                      | **DO**                                                       |
| 55   | Small-stuff sweep (24 TODOs, ~44 `print(` calls, repeated TODO banners) | **DEFER with details** — write to repo doc, enumerating the specific items |
| 56   | FileSync E2E encryption                                      | **NO**                                                       |
| 57   | Podping/WebSub instant feed updates                          | **DEFER** — write to repo doc                                |
| 58   | Peer-to-peer (LAN) sync                                      | **SKIP**                                                     |
| 59   | Server backend re-implementation spec                        | **DELETE** — remove `docs/ServerBackendSpec.md`              |
| 60   | Serverless Explore tab                                       | **DO**                                                       |
| 61   | ADRs for fork divergences                                    | **NO**                                                       |
| 62   | Automated upstream sync                                      | **NO**                                                       |
| 63   | Translation sync re-implementation                           | **NO**                                                       |
| 64   | OPML auto-export to sync folder                              | **NO**                                                       |
| 65   | Markdown bookmark export                                     | **DO**                                                       |
| 66   | iPad layout pass                                             | **NO**                                                       |
| 67   | Shake-to-report in beta                                      | **DEFER** — write to repo doc                                |
| 68   | Pseudo-localization snapshot job                             | **NO**                                                       |

### Follow-up decisions (AskUserQuestion, 2026-07-12)

1. **Stale flags scope:** retire only the **32 simple candidates** (1–4 call sites each); the 9 wide-adoption candidates (`onlyMarkPodcastsUnsyncedForNewUsers`, `autoDownloadOnSubscribe`, `generatedTranscripts`, `podcastFeedUpdate`, `searchImprovements`, `podcastsSortChanges`, `newOnboardingAccountCreation`, `useFollowNaming`, `optimizeManualPlaylistQueries`) are left for a later pass. `grdbQueryInterface` is retired via workstream 3, not the flag batches.
2. **Playback-adjacent flags:** retire **all 17** (`activateAudioSessionInBackground`, `avoidReplaceOnEpisodeSwap`, `doNotSwitchToDownloadedFile`, `dontAutoplayOnRouteChange`, `effectsPlayerQOSUpgrade`, `ignorePlayWithOtherAudio`, `ignoreRouteDisconnectedInterruption`, `playerIsReadyToPlay`, `replaceSpecificEpisode`, `limitPlaybackPositionChanges`, `whenPlayingOnlyUpdateEpisodeIfPlaybackFails`, `checkFinishedTimeBeforeShouldKeepPlaying`, `defaultPlayerFilterCallbackFix`, `useDefaultPlayerTapCookie`, `streamAndCachePlayingEpisode`, `trackNetworkDataUsage`, `upNextShuffle` — the last as its own PR).
3. **Refresh when signed in:** **server refresh stays** for signed-in users; automatic on-device refresh applies to signed-out users. The existing per-podcast `refreshSource` machinery handles the partition.
4. **Semantic search:** design doc only (`docs/SemanticSearch.md`), implementation deferred.

---

## Program structure

Work is organized into tracks. Within a track, items are sequenced; across tracks, work can proceed in parallel. Every PR passes the existing gates: `mise run build:staging`, `mise run test:staging`, `mise run check:static`, `mise run check:concurrency` (empty baseline must stay empty).

| Track                   | Contents (item #s)                                           |
| ----------------------- | ------------------------------------------------------------ |
| A — Local-first core    | 1 FileSync ungate · 2 signed-out local refresh · 6 storage local-always/sync-optional + flag un-gates |
| B — Data layer          | 3 raw-SQL → GRDB query interface · 26 ValueObservation       |
| C — Typed notifications | 4 (executes existing plan doc phases 4–6)                    |
| D — Flag retirement     | 5 (32 simple + 17 playback per follow-up answers)            |
| E — Player features     | 11 loudness normalization · 13 smart skip · 17 route-aware rules |
| F — System surfaces     | 12 Live Activity · 15 Control Center · 25 App Intents consolidation · 27 MetricKit · 28 TipKit |
| G — Content & UX        | 21 transcript reader · 60 Explore tab · 65 bookmark export   |
| H — Testing & CI        | 31 CI targets · 34 themed snapshots · 36 FeedParser fuzz · 37 FileSync simulation · 38 mutation testing · 44 build-time trends · 51 `@unchecked Sendable` gate |
| I — Cleanup & codegen   | 53 MNAVChapterReader port · 54 theme codegen · 59 delete backend spec |
| J — Documentation       | 10 fingerprint doc · 20 semantic-search design doc · `docs/DeferredWork.md` for all 17 deferred items |

---

## Track E — Player features

### E1. Loudness normalization (item 11)

**Key discovery: the hard part already exists.** The fork ships an ITU-R BS.1770-4 / EBU R128-compliant loudness engine:
- `podcasts/VoiceBoostN.c` / `.h` / `VoiceBoostN_Internal.h` — LUFS measurement, adaptive gain, compression, true-peak limiting (4× oversampled). API: `VBN_CreateWithConfig`, `VBN_Process`, `VBN_GetMeasuredLUFS`, `VBN_SetInitialGainDB`, `VBN_GetTargetLUFS`.
- `podcasts/AdvancedAudio/VoiceBoostNMeter.c` / `.h` — offline integrated-loudness meter with BS.1770-4 two-pass gating (`VBN_MeterCreate/Process/IntegratedLUFS`).
- `podcasts/AdvancedAudio/EpisodeLoudnessScanner.swift` — scans on download, persists via `DataManager.saveLoudness(episode:loudness:)` / `findLoudness(episode:)`; VBN seeds start gain from cached LUFS.

**Work:** add a user-facing **"Normalize volume"** effect distinct from full VoiceBoost — pure gain-to-target-LUFS (meter + static gain + true-peak safety limiter, no compression):
1. New tuning fields in `podcasts/AdvancedAudio/AudioTuning.swift` (target LUFS for normalization; reuse `VoiceBoostTuning` fields where sensible) — persisted as the existing JSON blob via `Settings.audioTuning`, consumed through `PlaybackManager.engineState` (`EngineStateMirror`, `PlaybackManager.swift:91`) per the established thread-safety pattern (audio threads never read `UserDefaults`).
2. `EffectsPlayer` path: apply gain per-buffer in `AudioReadTask.readFromFile()` (where `VBN_Process` already runs, lines ~280–300), configured via `AudioTuning+VBN.swift` `vbnConfig()` in a "normalize-only" mode (compressor bypassed, limiter kept).
3. `DefaultPlayer` (streaming) path: same via the existing `MTAudioProcessingTap` (`createAudioMix`, `DefaultPlayer.swift:436–473`; `tapProcess` 556–648) seeded from `cachedLoudness`. Document the limitation: no offline pre-scan for undownloaded streams; VBN adapts live until a cached LUFS exists; tap doesn't run for AirPlay-2 offloaded output.
4. Effects UI: add the toggle to `EffectsViewController.swift` (global) and per-podcast via `PodcastSettings` (`Modules/Sources/PocketCastsDataModel/Public/Model/PodcastSettings.swift`) following the `PlaybackEffects.effectsFor(podcast:)` pattern (`podcasts/PlaybackEffects.swift`).
5. Interlock with `voiceBoostN` un-gating (Track A): when both VoiceBoost and Normalize are on, VoiceBoost wins (it already normalizes); UI should communicate this.

### E2. Chapter-aware smart skip (item 13)

**Existing machinery:** per-episode chapter deselection already auto-skips — `ChapterInfo.shouldPlay`, episode column `deselectedChapters` (comma-separated indices; `BaseEpisode+Chapters.swift`, `EpisodeDataManager.swift:47/389/534`), enforcement in `PlaybackManager.playableChaptersUpdated()` (line 549) and the per-tick path (557–563) → `skipToNextChapter()`; toggles in `ChaptersViewController+Table.swift` / `ChaptersHeader.swift`.

**Work:** per-podcast auto-skip rules matched against chapter titles:
1. New setting on `PodcastSettings` (alongside existing `autoStartFrom`/`autoSkipLast`): list of case-insensitive title patterns (e.g. "ad", "sponsor", "intro").
2. Apply in `ChapterManager.handleChaptersLoaded` (where `episode.deselectedChapters` is already applied, lines ~256–262): chapters whose title matches a rule get `shouldPlay = false` (visually indicated as auto-deselected; user can re-enable per episode, which records an exception).
3. Rules UI in podcast settings (`PodcastSettingsViewController`), plus a "skipped by rule" toast/analytics via the existing `trackChapterSkipped()`.
4. Chapter sources already merged with precedence embedded > podcast-index > podlove/show-notes > generated (`ChapterOrigin`, `ShowInfoCoordinator.loadChapters`) — rules apply post-merge so they work for all origins including `generatedChapters` (un-gated in Track A).

### E3. Route-aware playback rules (item 17)

**Existing machinery:** `PlaybackManager.observeAudioSessionNotifications` (~line 237) → `handleRouteChanged(_:)` (line 2129): `oldDeviceUnavailable` → hard-wired pause (`player?.routeDidChange(shouldPause: true)`); `newDeviceAvailable` → no pause; AirPlay switch honors `FeatureFlag.dontAutoplayOnRouteChange`. `logRouteChange(userInfo:)` (2157–2169) already extracts previous/current route `portName`s — the natural capture point for `portType` too. No per-device settings exist today.

**Work:**
1. A `RouteRulesStore` keyed by route identity (`portType` + `portName`): per-route options — auto-resume on connect (default off), pause on disconnect (default on, making today's hard-wired behavior configurable), optional per-route effects profile (speed/trim/boost preset).
2. Enforce in `handleRouteChanged`: on `newDeviceAvailable` consult the rule for the new route (auto-resume replaces the blanket `dontAutoplayOnRouteChange` behavior for that route); on `oldDeviceUnavailable` consult pause rule.
3. Settings UI: a "Devices" section (list of recently seen routes, captured at `logRouteChanged` time) under playback settings; per-device rule editor. Recently-seen routes persisted via the standard settings store.
4. Retirement interlock: `dontAutoplayOnRouteChange` is in the playback-flag retirement batch (Track D) — land its retirement together with this feature so the behavior has one owner.

## Track F — System surfaces

### F1. Now Playing Live Activity + Dynamic Island (item 12)

Nothing exists (zero ActivityKit references). Build:
1. `PocketCastsLiveActivity` attributes type (episode uuid/title, podcast title, artwork ref, chapter title, playback state, position/duration) in a file shared app↔widget target; the widget-side `ActivityConfiguration` lives in `WidgetExtension/` (bundle entry `WidgetExtension/PocketCastsWidgetBundle.swift`) — Live Activities ship inside the existing widget extension, no new target.
2. Lock-screen presentation + Dynamic Island (compact: artwork + play state; expanded: artwork, titles, chapter progress, ±skip buttons). Controls fire the existing `PlaybackControlIntent` (`podcasts/PlaybackControlIntent.swift`, `AudioPlaybackIntent`, background-capable) through `PlaybackIntentActionHandler.shared` (`podcasts/PlaybackIntentActionHandler.swift`) — the exact pattern the iOS 18 Control Center widgets use.
3. App-side lifecycle manager (start on play, update on chapter/position cadence ~ once per significant change, end on stop/idle) hooked into `PlaybackManager` state transitions; artwork passed as file URL in the app group container (`SharedConstants.GroupUserDefaults.groupContainerId`), reusing `WidgetHelper.swift` conventions.
4. `NSSupportsLiveActivities` in `podcasts/Info.plist`.
5. Note: system Now Playing already appears on lock screen via `MPNowPlayingInfoCenter` (`NowPlayingHelper.swift`); the Live Activity adds the Dynamic Island + richer chapter surface. Avoid duplicate lock-screen chrome by scoping the Live Activity content (chapter + queue context) distinct from the system player.

### F2. Expand Control Center controls (item 15)

Existing: three `ControlWidget`s in `WidgetExtension/Controls/PlaybackControls.swift` (`PlaybackPlayPauseControl`, `PlaybackSkipBackControl`, `PlaybackSkipForwardControl`), control kinds `au.com.shiftyjelly.pocketcasts.control.*`, state via `PlaybackStateControlProvider` → `CommonWidgetHelper.loadPlayingStatus()`; refresh via `ControlCenter.shared.reloadControls` in `PlaybackIntentActionHandler.refreshWidgets()`.

**Work:** add controls following the same pattern: **sleep-timer control** (fires existing `SetSleepTimerIntent`/`ExtendSleepTimerIntent` from `podcasts/PocketCastsAppIntents.swift`), **next-chapter control** (`NextChapterIntent`), and **play-Up-Next control** (`PlayUpNextIntent`). All intents already exist — this is widget-side surface only.

### F3. Consolidate SiriKit onto App Intents (item 25)

Modern side already present: `podcasts/PocketCastsAppIntents.swift` (`ResumePlaybackIntent`, `PausePlaybackIntent`, `PlayUpNextIntent`, `PlaySuggestedEpisodeIntent`, `NextChapterIntent`, `PreviousChapterIntent`, `SetSleepTimerIntent`, `ExtendSleepTimerIntent`, `PocketCastsAppShortcuts: AppShortcutsProvider`), `PlayEpisodeIntent`, `PlaybackControlIntent`, all executing through `PlaybackFacade`/`LivePlaybackFacade`.

Legacy to remove: extension targets `PodcastsIntents/` (7 files incl. `PlayMediaIntentHandler.swift`, `ChapterIntentHandler.swift`, `OpenFilterIntentHandler.swift`, `SleepTimerIntentHandler.swift`, `SiriPodcastSearchManager.swift`) and `PodcastsIntentsUI/`; generated `podcasts/Intents Generated/SJ*` classes; `SiriShortcutsManager.swift` donations; `AppDelegate+SiriShortcuts.swift` INIntent handling; `SiriSettingsViewController.swift` (+ cells, `SiriPodcastItem.swift`, `PodcastSettingsViewController+VoiceShortcuts.swift`); ~70 pbxproj references; `com.apple.developer.siri` entitlement kept (App Intents still use it).

**Confirmed functional gap:** `INPlayMediaIntent` + `SiriPodcastSearchManager.matchUtteranceToPodcast` (`PodcastsIntents/PlayMediaIntentHandler.swift:33–45`) is the ONLY path supporting Siri "Play *<podcast name>* in Pocket Casts" natural-language phrasing, and `AppDelegate+SiriShortcuts.handlePlayMediaIntent` applies spoken playback speed. Migration plan:
1. Introduce `PodcastAppEntity` (+ `EntityQuery` backed by the same app-group podcast list `SiriPodcastSearchManager` uses) and a parameterized `PlayPodcastIntent`; equivalent `FilterAppEntity`/`OpenFilterIntent` replacing `SJOpenFilterIntent`.
2. Port chapter/sleep-timer/open-filter `SJ*` flows onto the existing App Intents (mostly done — delete generated classes and NSUserActivity dispatch in `AppDelegate+SiriShortcuts.handleContinue`).
3. **Decision point (asked below): whether to accept the reduced "play <show>" Siri phrasing** that `AppIntents` media search offers vs. keeping a minimal `PodcastsIntents` extension solely for `INPlayMediaIntent`.

### F4. MetricKit ingestion (item 27)

Zero MetricKit usage today (verified). Add a `MetricKitCollector` (`MXMetricManagerSubscriber`) registered via a `configureMetricKit()` call in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` alongside the existing `configureBitdrift()` / `configureTelemetryDeck()` calls (`podcasts/AppDelegate.swift:32–127`, analytics config ~line 43): persist `MXMetricPayload`/`MXDiagnosticPayload` JSON to a local ring buffer (`FileLog`-adjacent directory), surface crash/hang/launch-time summaries through the existing `AnalyticsAdapter.track(name:properties:)` seam (`podcasts/Analytics/Adapters/TelemetryDeckAnalyticsAdapter.swift` stringifies `[String: Sendable]` properties — MetricKit scalars/histograms fit; the existing opt-out in `podcasts/PrivacySettings/` is honored automatically by the adapter fan-out), and add a debug viewer row in the Beta menu (`podcasts/Beta/BetaMenu.swift`). No third-party SDK.

### F5. TipKit feature discovery (item 28)

**Replaces an existing custom system** (verified): `podcasts/TipView.swift` + per-feature tips (`podcasts/Podcasts/All Podcasts/PodcastListViewController+Tip.swift`, `PlaylistsViewController+Table.swift`, `NewPlaylistViewController.swift`) driven by `Settings.shouldShow…Tip` booleans (`shouldShowNewFilterTip`, `shouldShowPodcastFeeReloadTip`, `shouldShowPodcastViewChangesTip`, `shouldShowRecentlyPlayedSortingTip`, `shouldShowPlaylistsOnboarding` — toggled at `podcasts/AppDelegate.swift:59–66` on install/upgrade). The dead "What's New" persistence keys (`Settings.swift:686–705`) get cleaned up in the same pass.
**Work:** configure TipKit at launch; migrate the four existing `TipView` usages to `Tip` types (donate the same install/upgrade events); add tips for the program's new/un-gated features: Up Next sort (Track A), transcript reader (G1), smart skip rules (E2), Control Center controls (F2). Delete `TipView.swift` and the `shouldShow…Tip` settings when the last usage migrates.

## Track G — Content & UX features

### G1. Transcript reader mode — all parts (item 21)

Existing stack: `TranscriptModel` stores `AttributedString` + `cues: [TranscriptCue]` with `characterRange`s (PR #269); follow-along highlighting already works via `CADisplayLink` + fingerprint gating (`TranscriptViewController.swift:857–985`, highlights only when `FingerprintTimingManager.shared.state == .active`); KMP-based in-transcript search already exists (`kmpSearch`, line 1066, `TranscriptSearchAccessoryView`); share today = whole-transcript plain text (`shareEpisode()`, line 373); tap-to-seek via `FingerprintTimingManager.playbackTime(forReferenceTime:)` (line 1021).

**Work (the deltas):**
1. **Reader view**: a full-screen, typography-first presentation (SwiftUI) of `TranscriptModel.attributedText` with speaker runs (`TranscriptSpeakerAttribute`) styled, adjustable text size, and the existing highlight/auto-scroll engine reused. Entry from the transcript shelf (`TranscriptShelfButton.swift`) and episode detail.
2. **Quote-share**: text selection → share selected cue range as (a) text quote with episode attribution/timestamp link, and (b) audio clip — map the selected cues' `startTime…endTime` through the existing clip exporter (`podcasts/Sharing/Clip/AudioClipExporter.swift` / `SharingModal.swift`), pre-seeding the trim range.
3. **Search in reader**: reuse `kmpSearch` + `TranscriptSearchHighlightStyle`.
4. Keep `TranscriptViewController` (1,372 lines) untouched where possible — reader is additive; extraction of shared highlight logic into a helper is in-scope only if reuse forces it (VC split itself is deferred, item 8).

### G2. Serverless Explore tab (item 60)

Tab construction: `podcasts/Main/MainTabBarController.swift` — `enum Tab { podcasts, filter, profile }` (line 11), tabs built in `viewDidLoad` (96–112) as `pcTabs = [.podcasts, .filter, .profile]`; `LegacyTab` migration precedent (`restoredLastTabIndex`/`migratedLastTabIndex`, lines 259–278) shows exactly how to evolve persisted tab indices.

**Work:**
1. Add `case explore` to `Tab`, append to `pcTabs`, new `ExploreViewController` (SwiftUI host) wrapped via `SJUIUtils.navController(for:)`; extend `trackTabOpened` analytics.
2. Content **without the Pocket Casts server**: iTunes/Apple Marketing charts feeds (keyless: `itunes.apple.com` top-podcasts RSS per country + genre) for charts and categories; search via existing search UI (`podcasts/New Search/`) — note current `PodcastSearchTask` hits the PC server; Explore's serverless search uses the iTunes Search API and resolves results to feed URLs.
3. Subscribe flow routes through the **local pipeline** (`ServerPodcastManager.addLocalFeed`, feed-URL dedup via `DataManager.findPodcast(feedURL:)`) so Explore works fully signed-out — this is the Track A partition rule applied to new adds.
4. Reuse cells: `DiscoverPodcastTableCell.swift`, onboarding grid patterns (`podcasts/Onboarding/DiscoverPodcastsGridView.swift`). The old `DiscoverServerHandler` (`Modules/Sources/PocketCastsServer/Public/Discover/DiscoverServerHandler.swift`) stays untouched (used by onboarding recommendations) — Explore does not depend on it.

### G3. Markdown bookmark export (item 65)

Existing: `BookmarkManager` (`podcasts/BookmarkManager.swift`) with `allBookmarks(sorted:)` / `bookmarks(for:)`; model `Bookmark` (uuid, title, `time: TimeInterval`, `created`, episode/podcast refs) at `Modules/Sources/PocketCastsDataModel/Public/Bookmarks/Bookmark.swift`; share today routes a single bookmark into clip sharing (`BookmarkListViewModel.shareSelectedBookmarks()`, `BookmarkListRouter.bookmarkShare`). No text export exists.

**Work:** a `BookmarkMarkdownExporter` (formats per-podcast → per-episode groups; each bookmark as `- [HH:MM:SS] Title (created date)` with episode/podcast headers and share links) + export actions: "Export All" from the Profile bookmarks list and per-podcast/per-episode lists (`Bookmarks/List/BookmarksListView.swift` action bar, extending the existing multi-select), delivered via `UIActivityViewController` as `.md` file.

---

## Track C — Typed NotificationCenter migration (item 4)

**Executes an already-written plan:** `docs/Swift 6.3 + iOS 26 Full Migration Plan — Pocket Casts iOS.md`, Phases 4–6. Summary of what that document specifies (it remains the source of truth):
- Phase 4 (1 PR): infrastructure + spike — all messages as `NotificationCenter.MainActorMessage` (every custom post already funnels through `NotificationCenter.postOnMainThread`, `Modules/Sources/PocketCastsUtils/Extensions/NSNotificationCenterExtension.swift`); one struct per notification in new `podcasts/Notifications/` (PlaybackMessages, EpisodeMessages, UpNextMessages, PodcastMessages, UIMessages, AccountMessages; server-side in `Modules/Sources/PocketCastsServer/Public/ServerNotifications.swift`); `UuidBridgedMessage` protocol for the ~30 uuid-in-object names; typed `postOnMainThread<M>` helper preserving main-sync semantics; token bags extended on `podcasts/SimpleNotificationsViewController.swift` and `podcasts/Utilities/CustomObserver.swift`. Spike message: `EpisodePlayStatusChanged` (posts `podcasts/EpisodeManager.swift:36,148`, ~12 observer sites enumerated in the doc).
- Phase 5 (6 PRs): domain sweeps — 5.1 episode status (`EpisodeCell` 18 observers first), 5.2 playback (~15 names), 5.3 Up Next, 5.4 podcast/folder/filter/discover, 5.5 server module (17 `ServerNotifications`), 5.6 UI chrome + account.
- Phase 6 (1 PR): delete `Constants.Notifications` (`podcasts/Constants.swift:6–99`), `podcasts/Notifications.swift`, `NSNotification.Name` constants.

**Program-level coordination (new):** Track B's `ValueObservation` pilots replace some *DB-changed* notifications on pilot screens. Rule: a screen adopted by a ValueObservation pilot is skipped in the corresponding Phase-5 sweep (the notification post stays for other observers until zero refs, then dies in Phase 6 or the pilot PR). Sequence the spike (Phase 4) before the first ValueObservation pilot so both patterns are visible side by side and the choice per screen is recorded in the PR description.

## Track D — Feature-flag retirement (item 5 + follow-up answers)

**Process:** per `docs/FeatureFlagAudit.md` — remote-config sign-off recorded in the audit table per flag (each has a live remote kill-switch key derived from `rawValue.lowerSnakeCased()`), then removal PR (inline `true` branch, delete `false` branch + enum case + `default` arm). Batches of 3–5 related flags per PR.

**D1 — the 32 simple candidates (user-approved):**
`activateAudioSessionForRoutePicker`, `checkProtectedDataBeforeMigration`, `detectTruncatedBackgroundSyncDownloads`, `encourageAccountCreation`, `episodeDetailTranscript`, `listeningHistorySearch`, `logMainThreadDatabaseAccess`, `manageDownloadedEpisodes`, `newOnboardingRecommendationChanges`, `podcastBookmarksInline`, `retryWithoutUserAgent`, `shareTranscripts`, `skipSyncWhenProtectedDataUnavailable`, `streamingCustomSessionConfiguration`, `useBackgroundQueueForStreamingCallback`, `useDescriptiveActionAttributedTextView`, `useMimetypePackage`, `cleanUpTmpFiles`, `concurrentDatabaseReads`, `customPlaybackSettings`, `downloadsThreadSafeCache`, `enableLocalizationHeaders`, `markAllSyncedInSingleStatement`, `searchPredictive`, `statsHeatmap`, `suggestedFolders`, `displayErrorsOnPlayer`, `releaseMediaExporterWhenNoLongerActive`, `useCellularNetworkApis`, `playlistCacheInvalidation`, `playlistDataCacheBeforeQuery`, `recommendations`.
Suggested batching: by subsystem (downloads/streaming ×6, sync/migration ×4, playlists ×2, search ×2, UI one-liners ×6, misc). **Coordination:** `concurrentDatabaseReads` branches `GRDBQueue.swift:50,84` — retire inside Track B's data-layer work, not a batch PR, to avoid conflicts.

**D2 — all 17 playback-adjacent flags (user-approved, Recommended option):**
`activateAudioSessionInBackground`, `avoidReplaceOnEpisodeSwap`, `doNotSwitchToDownloadedFile`, `dontAutoplayOnRouteChange`, `effectsPlayerQOSUpgrade`, `ignorePlayWithOtherAudio`, `ignoreRouteDisconnectedInterruption`, `playerIsReadyToPlay`, `replaceSpecificEpisode`, `limitPlaybackPositionChanges`, `whenPlayingOnlyUpdateEpisodeIfPlaybackFails`, `checkFinishedTimeBeforeShouldKeepPlaying`, `defaultPlayerFilterCallbackFix`, `useDefaultPlayerTapCookie`, `streamAndCachePlayingEpisode`, `trackNetworkDataUsage`, `upNextShuffle` (own PR — 14 call sites).
Small batches (3–4), each exercised by `mise run test:staging` playback suites + a manual playback QA checklist (play/pause/seek/route change/stream/download/Up Next). **Coordination:** `dontAutoplayOnRouteChange` retires together with Track E3 (route-aware rules absorb the behavior).

**Explicitly NOT retired now** (user decision): the 9 wide-adoption candidates — `onlyMarkPodcastsUnsyncedForNewUsers`, `autoDownloadOnSubscribe`, `generatedTranscripts`, `podcastFeedUpdate`, `searchImprovements`, `podcastsSortChanges`, `newOnboardingAccountCreation`, `useFollowNaming`, `optimizeManualPlaylistQueries`.
**Bookkeeping:** update stale `docs/FeatureFlagAudit.md` rows: `grdbQueryInterface` is ALREADY deleted from the enum (audit line 71 is stale); add rows for post-audit flags (`syncedTranscripts`, `showExplicitBadges`, `fileSync`, `upNextSort`, `generatedChapters`); record the four Track-A un-gates.

## Track H — Testing & CI

### H1. SnapshotTests + GRDBMacrosTests in CI (item 31)

Facts: neither target is in any `.xctestplan`; no shared scheme exists for them; no `swift test` job exists. `scripts/ci/check-test-targets.sh` requires each expected bundle to have ≥1 **non-skipped** test case.
1. **SnapshotTests** (simulator-capable — helpers are `#if canImport(UIKit)`, render via `UIHostingController`): append to `PocketCastsTests/UnitTests.xctestplan` using the SPM entry shape `{ "target": { "containerPath": "container:Modules", "identifier": "SnapshotTests", "name": "SnapshotTests" } }`; add `SnapshotTests` to `scripts/ci/expected-test-targets.txt`. Reference images are committed under `Modules/Tests/SnapshotTests/__Snapshots__/` (excluded from the target via `exclude` in `Modules/Package.swift:231`); CI never sets `SNAPSHOT_TESTING_RECORD`.
2. **GRDBMacrosTests must NOT go in the simulator plan**: every test is fenced `#if canImport(GRDBMacrosPlugin)` with `throw XCTSkip(...)` otherwise (`GRDBRecordMacroTests.swift:91–93` et al.) — all-skipped would fail `check-test-targets.sh`. Add a **macOS host job** to `.github/workflows/ios-ci.yml` running `swift test --package-path Modules --filter GRDBMacrosTests` (fast; no simulator).
3. Wire `scripts/ci/check-snapshot-coverage.rb` (90% threshold; groups `ui`: GradientView.swift, `logic`: PlaylistQueryBuilder/SignificantDigitsFormatStyle/UIColorExtension) into the **test job** after the run — it consumes `xcrun xccov view --report --json` from the produced `.xcresult`, so it cannot live in `check:static`. Update its group lists as H2 adds views.

### H2. Themed snapshot coverage (item 34)

Facts: `assertThemedSnapshots` (`Modules/Tests/SnapshotTests/SnapshotTestHelpers.swift:24–36`) varies `UIUserInterfaceStyle` (light/dark) × `UIContentSizeCategory` only — it does NOT iterate the app's 9 custom themes (light, dark, extraDark, electric, classic, indigo, rosé, contrastLight, contrastDark). The SPM `SnapshotTests` target **cannot see app views** (depends only on DataModel/Utils; zero SwiftUI views exist in `Modules/Sources/`; the app's 231 SwiftUI views live in `podcasts/`).
1. Follow `docs/snapshot-testing.md:109–126`: add the `SnapshotTesting` package product to the **PocketCastsTests app-test target** (Xcode project edit), and write an app-target helper `assertAppThemedSnapshots` that hosts a view with `.environmentObject(Theme(previewTheme: themeType))` looping all 9 `ThemeType` cases (× light/dark trait where relevant) — reusing the SPM helper's naming convention (`named: "\(theme)-\(sizeCategory)"`).
2. Seed with ~10 deterministic, dependency-light SwiftUI views: `podcasts/Sharing/PocketCastsLogoPill.swift`, `podcasts/Sharing/ShareButton.swift`, `podcasts/Sharing/Clip/PlayButton.swift`, `podcasts/Onboarding/InterestButton.swift`, `podcasts/Onboarding/PodcastSubscribeButton.swift`, `podcasts/New Search/Views/Results/RoundedSubscribeButtonView.swift`, `podcasts/Folders/Create & Edit/Views/ColorSelectRow.swift`, `podcasts/Profile - SwiftUI/Common Views/ProfileInfoLabels.swift`, `podcasts/ModalCloseButton.swift`, `podcasts/AdvancedAudio/TuningRows.swift`. Grow opportunistically with each Track E–G feature (new views land with snapshots).
3. Record baselines on the CI-pinned simulator/runtime per `docs/snapshot-testing.md`; commit under the app-test target's snapshots directory.

### H3. FeedParser property/fuzz tests (item 36)

Facts: `FeedParserTests.swift` is Swift Testing (`@Suite("FeedParser")`) with exactly one parameterized test (`@Test("duration formats", arguments:)` lines 155–163); fixtures are inline strings; the target has a `Fixtures/` resource dir (`Modules/Package.swift:178`). `FeedParser.parse(data:) throws -> ParsedFeed` is pure data-in/struct-out over Foundation `XMLParser`.
1. **Corpus tests:** add `Fixtures/Feeds/` with real-world weird feeds (huge feeds, BOM/encoding variants, CDATA-heavy, mixed namespaces, RFC-5005 paged, malformed-but-recoverable) + hostile inputs (XXE payloads `<!ENTITY`, billion-laughs, deeply nested elements, truncations at every N bytes of a valid feed) — parameterized `@Test(arguments:)` over the directory listing; invariants: no crash/hang, either `ParsedFeed` or a thrown `FeedParserError`, XXE never resolves (no file/network content in output).
2. **Property-style generators (no new dependency):** seeded pseudo-random feed generator (element shuffling, attribute dropping, entity injection, byte mutations of a valid fixture) with fixed seeds via `@Test(arguments:)` — deterministic, CI-friendly. Round-trip invariants: `LocalFeedIdentity` stability (same guid/enclosure → same uuid), date/duration parser totality (`FeedDateParser`, `FeedDurationParser` never crash on arbitrary strings).
3. Time-box the parse in tests to catch pathological blowups (XMLParser entity expansion) — assert wall-clock bound.

### H4. FileSync merge-engine simulation tests (item 37)

Facts: `MergeEngine.merged(snapshots:ops:)` is a pure static function ("No I/O and no database access"); `OpStamp` is a total order (wallClockMs, deviceID, seq); `UpNextMerger.replay(ops:)` pure; `InMemorySyncFolder` actor harness exists (fixed mtime, deterministic listings); existing `MergeEngineTests` already assert order-independence + idempotence. **The only non-deterministic seam: `FileSyncClock.currentUTCTimeInMillis()` reads `Date()` directly** (consumed at `FileSyncBootstrap.swift:21`, `OpJournalFlusher.swift:76,108`).
1. **Clock injection PR:** introduce a `now: () -> Int64` seam (default `FileSyncClock.currentUTCTimeInMillis`) through `OpJournalFlusher`/`FileSyncBootstrap` so simulations control time. Mechanical; no behavior change.
2. **Simulation suite** (`Modules/Tests/PocketCastsFileSyncTests/MergeSimulationTests.swift`): N virtual devices (2–5), seeded RNG generating interleaved op schedules (episode field writes, podcast writes, Up Next ops, tombstones, resurrections, settings) with skewed clocks and duplicated/reordered delivery via `InMemorySyncFolder`s; invariants per seed: **convergence** (all devices reach identical `MergedState` regardless of ingest order), **idempotence** (re-applying any log prefix is a no-op), **snapshot equivalence** (snapshot+tail == full replay — extends the existing golden test), **monotonicity** (an op never resurrects data a newer tombstone killed). Run a fixed seed matrix in CI; log the failing seed for reproduction.

### H5. Mutation testing (item 38)

Greenfield (no `.muter.conf`). Scope to the SPM module suites (DataModel 539 tests, Utils 98, FileSync 68) where tests are fast and hermetic: add `muter` config targeting `Modules/Sources/PocketCastsDataModel` + `PocketCastsUtils` + `PocketCastsFileSync`, run via a manual/nightly workflow (not per-PR — runtime), triage surviving mutants into test-gap issues. First measure per-target runtimes from an `.xcresult` to size the job.

### H6. Build-time trends (item 44)

Facts: `-debug-time-function-bodies` is already injected in the Danger job only (`.github/workflows/danger.yml:44` → `POCKET_CASTS_CI_OTHER_SWIFT_FLAGS`, consumed by `scripts/ci/build-and-test.sh:51–53`); frontend timings land in `build/github/logs/test-staging.log` (uploaded as artifact; on disk when `bundle exec danger` runs in the same job). `Dangerfile` today reports rubocop, manifest sync, view changes, `xcode_summary`, slather — no timing parse.
**Work:** a Ruby helper (invoked from `Dangerfile` after the `xcode_summary.report` block) that greps the `^\d+\.\d+ms\t` frontend lines from the log, aggregates per function/file, and posts a markdown table of the top ~20 slowest function bodies + total, so PRs show compile-time regressions as a trend.

### H7. Activate the `@unchecked Sendable` gate (item 51)

Facts: the count ratchet already blocks new usages per-file (`scripts/ci/check-count-ratchets.sh`, baseline `scripts/ci/ratchet-unchecked-sendable.txt`, format `path: count`; currently 137 total = 122 production + 15 tests; largest: generated `api.pb.swift` ×13). The model rule exists: `pocketcasts.nonisolated-unsafe-requires-justification` (`semgrep/swift-security.yml:4752`) — regex + `pattern-not-regex` exempting a same-line/preceding `// nonisolated(unsafe): <reason>` comment; plus `pocketcasts.grdb-record-no-unchecked-sendable-class` (:4776).
**Work:** add `pocketcasts.unchecked-sendable-requires-justification` cloned from the model rule (token swapped; `// @unchecked Sendable: <reason>` comment format), with `paths.exclude` for generated protobuf (`**/*.pb.swift`) and `Modules/Sources/PocketCastsDataModelTesting/**` mocks; annotate the remaining production sites in mechanical batches (the API-task family shares one rationale) as part of rollout; add fixture pairs under `semgrep/tests/` (the runner enumerates them in `scripts/ci/run-semgrep-tests.sh`). The count ratchet stays as the complementary cap.

## Track I — Cleanup & codegen

### I1. Port MNAVChapterReader; retire last ObjC (item 53)

Facts: MNAV (`podcasts/Third Party Libraries/MNAVChapters/MNAVChapterReader.{h,m}`, 507-line .m) parses **embedded** chapters only — ID3v2 CHAP/CTOC frames (MP3) and MP4 chapter tracks; single Swift call site `podcasts/PodcastChapterParser.swift:98–147` (`parseChapters(url:episodeDuration:)`, wrapped in `SJCommonUtils.catchException`, result mapped to `ChapterInfo`). Non-embedded chapter sources (Podlove JSON, Podcast Index, generated) are already pure Swift in the same class.
1. New `EmbeddedChapterParser` (Swift): MP4/m4a via `AVAsset.loadChapterMetadataGroups`/`AVTimedMetadataGroup` (system API covers chapter tracks incl. artwork); ID3v2 CHAP/CTOC via a small hand-rolled frame parser over the file's ID3 tag (bounded scope: v2.3/2.4, CHAP + CTOC + embedded APIC artwork). Fixture-driven tests with sample MP3/M4A files (new fixtures under `PocketCastsTests`).
2. Cut `PodcastChapterParser` over, delete `MNAVChapterReader.{h,m}`, drop its import from `podcasts/podcasts-Bridging-Header.h` (header keeps `SJCommonUtils.h` — NSException trapping is unportable per MODERNIZATION.md — and `VoiceBoostN`/meter imports).
3. Remaining ObjC bookkeeping (from MODERNIZATION.md Phase 0): `SJMediaMetadataHelper` async port lands only if its flow is touched; `NSNull+Length` deletion still requires crash-log archaeology — both recorded in `docs/DeferredWork.md` (item 55 adjacency), not this program.

### I2. Modernize theme codegen (item 54)

Facts: `scripts/themes/generate_themes.rb` reads `scripts/themes/theme.csv` (156 token rows × 9 emitted themes; "Classic Dark" columns parsed but unused) and regenerates `podcasts/ThemeColor.swift` (6,087 lines: per-token 9 `UIColor` constants + a `switch`-on-`ThemeType` accessor; special parameterized families for `podcast*`/`playerBackground*`/`playerHighlight*` (`podcastColor:`) and `filter*` (`filterColor:`) computing overlays via `UIColor.calculateColor(orgColor:overlayColor:)`) + `podcasts/ThemeStyle.swift` (token enum). Asset catalogs are a poor fit (only 2 appearance variants vs 9 themes; can't express overlay math; would need ~1,400 colorsets).
**Chosen approach — data-driven runtime table, API-stable:**
1. Generate (or bundle) a compact color table — `[ThemeType: [ThemeStyle: ColorSpec]]` (hex + alpha) — as a resource compiled from `theme.csv` (keep Ruby generator, emit JSON/plist + a tiny loader instead of 6k lines of Swift), preserving the parameterized overlay functions as hand-written Swift.
2. Keep the public surface identical: `ThemeColor.<token>(for:)` becomes a table lookup (one generated thin shim or a `ThemeStyle`-keyed accessor); `AppTheme.color(for:theme:)` (`podcasts/Theme+Color.swift`) and the `Theming` accessors are untouched. `ThemeType` stays in `Modules/Sources/PocketCastsServer/Public/ServerEnums.swift:51`.
3. Wins: compile-time drop (6k generated lines → data), themes editable without recompiling codegen output, and the unused Classic Dark columns get explicitly dropped or revived. Verify with H2's themed snapshots (they exist precisely to catch color regressions) + `mise run generate:colors` parity check (old vs new lookup for all 156×9 = 1,404 pairs in a unit test before deleting the old path).

### I3. Delete the backend spec (item 59)

Delete `docs/ServerBackendSpec.md`; update the companion cross-reference in `docs/ServerAPISurface.md` (its header cites the spec as "the implementation contract"). One-line note in the docs index if any (`docs/GettingStarted.md`).

## Track J — Documentation deliverables

### J1. Audio fingerprinting documentation (item 10) — new `docs/Fingerprinting.md`

Thorough system doc covering (all verified in code):
- **Purpose:** maps live playback time ↔ reference-transcript time via audio fingerprint matching so transcript follow-along/tap-to-seek stay correct when dynamic ad insertion shifts audio. Gated by `FeatureFlag.syncedTranscripts`.
- **Components:** `podcasts/Fingerprint/FingerprintConstants.swift` (all tuning: 8000 ms windows / 1000 ms interval, drift tolerances, `highlightMaxGapSeconds = 8`, cache schema v2, `fullCoverageThreshold = 0.95`); `FingerprintTimingManager.swift` (state machine idle/preparing/active(coverage:)/failed/unavailable; streams local audio via `AVAudioFile` incl. growing streaming buffer; drift filter; `TimeMappingEntry` anchor commits; public API `referenceTime(forPlaybackTime:)`, `playbackTime(forReferenceTime:)`, `isWithinMatchedContent`); `ReferenceFingerprint.swift` (server JSON `"fingerprint-compact-v2"`: checkpoints, quantum, base64-packed UInt32 hashes); `FingerprintReferenceRetriever.swift` (actor; gzip via Compression; 3 retries; in-flight dedup); `FingerprintMappingCache.swift` (`*.map.fp.json` beside audio; SHA-256 reference hash + audio size/mtime + 64 KiB sample + ≥95% coverage validity); `FingerprintDebugOverlay.swift` (DEBUG timeline view).
- **Dependency:** `Automattic/pocket-casts-ios-fingerprint` (pinned revision in `Modules/Package.swift:80`) — UniFFI Rust binding providing `CheckpointMatcher`, `StreamingWindowedFingerprinter`, `WindowedFingerprint`.
- **Server contract:** `{ServerConstants.Urls.generatedTranscripts}/{podcastUuid}/{episodeUuid}-fingerprints.json.gz` (`ServerConstants.swift:41`).
- **Consumers:** `TranscriptViewController` highlight/tap-to-seek (fingerprint-gated, lines 857–1021); relationship to `generatedTranscripts`/`syncedTranscripts` flags; tests (`PocketCastsTests/Tests/Fingerprint/`).

### J2. Semantic search design doc (item 20 — design ONLY, per follow-up answer) — new `docs/SemanticSearch.md`

Contents: goal (natural-language episode retrieval over show notes + transcripts); candidate embedding backends on iOS 26 (`NLEmbedding`/NaturalLanguage vs FoundationModels embedding, on-device only); storage design (new GRDB table `episode_embedding(episodeUuid, model, dims, vector BLOB)`, brute-force cosine at library scale ~10⁴ episodes, chunking strategy per transcript cue windows); indexing pipeline (on download/transcript availability, background, battery-aware); query flow (embed query → rank → group by episode → present in `podcasts/New Search/` UI as a "By meaning" section); privacy stance (nothing leaves device); open questions (model size/versioning, re-index policy, multilingual). Marked **not scheduled** — implementation deferred.

### J3. `docs/DeferredWork.md` — the deferred-items register (single consolidated doc)

One section per deferred item, each with: why deferred (user decision 2026-07-12), current state, concrete re-entry plan, and pointers. Items and required details:
- **DI call-site conversion (item 7):** remaining backlog by grep — `DataManager.sharedManager` ~446 sites/129 files, `PlaybackManager.shared` ~386/69 (engine/player-callback files stay on the singleton by design), `Theme.sharedTheme` ~273/68 (many `environmentObject` sites should not convert); pattern template = `PlaylistsViewController`/`ArchiveHelper`; known seam gaps (`activateAudioSession` missing from `PlaybackManaging`, `DataManager+FileSync` surface on no repository protocol) — from MODERNIZATION.md Phase 2 notes.
- **VC splits (item 8):** targets and sizes — `PlaybackManager.swift` 2,638, `PodcastViewController.swift` 1,738, `Settings.swift` 1,608, `TranscriptViewController.swift` 1,372, `MainTabBarController.swift` 918; original Phase-2 exit criterion (no non-playback file > 1,000 lines) stands unmet.
- **Swift Testing migration (item 9):** current mix ~1,255 XCTest methods vs 37 `@Test`; locked decision from the iOS-26 plan (modules migrate; app-target `PocketCastsTests` + `SnapshotTests` stay XCTest).
- **Adaptive effects switching (item 14):** concept (auto-suspend trim/boost during music via the existing SoundAnalysis VAD discriminator in `AdvancedAudio/TrimSilenceDetector.swift`); entry point `AudioReadTask`.
- **On-device transcription (item 18):** iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` for episodes lacking transcripts; feeds reader mode + (future) semantic search; storage via existing transcript cache.
- **FoundationModels episode intelligence (item 19):** summaries, catch-me-up, chapter-title generation; builds on `generatedChapters` UX.
- **`@Observable` migration (item 24):** 165 `@Published` / 57 `ObservableObject` / 0 `@Observable`; mechanical migration guide pointer.
- **SharePlay (item 29):** GroupActivities listening sessions concept.
- **Coverage floor + upload (item 33):** floor currently 2.0 (`scripts/ci/coverage-floor.txt`; real ~15% per its comment); Slather terminal-only in Danger; SonarCloud has no coverage wired (`sonar-project.properties`).
- **New-feature test debt (item 35):** untested areas — Player UIKit stack (~40 files), Onboarding (34), Settings VCs, New Detail (26), Sharing UI (21); lever = repository protocols + `@Dependency` mocks (`Modules/Sources/PocketCastsDataModelTesting/`).
- **Performance regression tests (item 39):** XCTMetric baselines for cold start / migrations (production fixtures exist: `ProductionDatabaseMigrationFixtureTests.swift`) / large-library scroll.
- **Dependency automation (item 45):** `spm-version-updates.yml` reports only; Renovate + osv-scanner + SBOM sketch.
- **Flat-root organization (item 49):** 367 flat files in `podcasts/`; move-only PR series by feature area.
- **SPM feature extraction (item 50):** candidates Bookmarks, Sharing, Onboarding, Analytics adapters.
- **Small-stuff sweep (item 55, with details as user requested):** the 24 TODO/FIXME sites (list the notable ones: `OptionsPicker.swift:51`, `UserEpisodeDetailViewController.swift:106` TODO-on-force-unwrap, `TopShadowView.swift:15` theme fix, `PlayerContainerViewController.swift:169/209/265` "Show install banner" ×3, `AppTheme.swift:538`, `FolderViewController.swift:251` diffable, `AddCustomViewController.swift:222`, `SuggestedFoldersView.swift:99` scroll-indicator hack, missing-analytics TODOs in `ManualPlaylistsChooserViewController.swift:328/337`, `PlaylistsViewController+Table.swift:237`, `PodcastViewController.swift:1408`); ~44 stray `print(` calls to route through `FileLog`; ~107 commented-out code lines.
- **Podping/WebSub (item 57):** instant local-feed updates; fits after Track A.
- **Shake-to-report (item 67):** extend `podcasts/BackgroundShakeObserver.swift` + bitdrift session attach into `SupportFeedbackRequest`.

---

## Track A — Local-first core (items 1, 2, 6)

**Design principles (fixed):** subscribe-time decision, not refresh-time — a persisted per-podcast `refreshSource` decided once is deterministic and inspectable; the existing `CompositeFeedRefreshProvider` partition does the rest. Existing server-sourced podcasts stay on server refresh forever (server refresh works signed-out — public endpoints; login only gates the post-refresh sync backfill at `RefreshManager.swift:49,66` and `syncUpNext` `:28-32`). `refreshSource` is sticky across sign-in/out — no transition code. No new scheduler is needed: refresh triggers (foreground timer `AppDelegate.swift:155`, BG app-refresh `:281`, remote-notification fetch `:173`, pull-to-refresh) are not login-gated.

**Verified facts that shaped the design:** `Episode` has NO guid column — identity matching must use `downloadUrl` (enclosure) with title+publishedDate fallback. The show-notes cache is one blob per podcast and local seeding overwrites it; `ShowInfoCoordinator.swift:144-145` reads cache-only for `.localFeed` podcasts — so seeding must key entries by *resolved* episode UUIDs or back-catalog show notes disappear (hard requirement on A2). `addPodcast` already threads `refreshSource:` and forces `syncStatus = .synced` for `.localFeed` rows (`ServerPodcastManager.swift:271-275`); the subscribe-in-place branch (`:248-267`) does not touch `refreshSource` and must.

**Merge order: A1, A4, A5, A2, A3** (small wins first; A2 → A3 strictly ordered).

### A1 — Delete `FeatureFlag.fileSync` (item 1; single PR)

1. `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`: delete case `:224` + default `:382-386` (remoteKey uses the default branch; nothing else to delete).
2. Unwrap 17 call sites keeping the flag-ON branch: `podcasts/SettingsViewController.swift:22` (row visibility; push at `:208-212` stays), `podcasts/UploadedViewController.swift:47,230,242,327`, `podcasts/UploadedStorageHeaderView.swift:62` (→ always iCloud label), `podcasts/Syncing/FileSync/FileSyncBanner.swift:11` (its second gate — UserDefaults `"FileSync.enabled"` + dismissal — stays), `podcasts/Syncing/FileSync/FileSyncCoordinator.swift:27,62,67,113`, `podcasts/UserEpisodeManager.swift:40,87,108,155,225`, `podcasts/DownloadManager+URLSessionDelegate.swift:210`.
3. Delete `podcasts/SceneDelegate.swift:201` (UI-test harness force-overrides the flag OFF; overriding a deleted flag won't compile). Audit `PocketCastsUITests/SmokeUITests.swift:575,640` (FileSync debounce marker) — Files-screen expectations change.
4. Update `docs/FeatureFlagAudit.md` (also fix its stale `grdbQueryInterface` row `:71` — already deleted from the enum).

**Risks:** App Store builds auto-enroll into iCloud FileSync on update when available (`FileSyncManager.enableICloudIfUnconfigured()` runs from `setup()`) — accepted by the user's "no gate" decision; the user-visible off switch (`FileSyncSettingsView` → `"FileSync.enabled"`) remains. BGTask `performBackgroundSync` (`AppDelegate.swift:280-284`) now runs in App Store builds — verify the task identifier is in the shared Info.plist once.
**QA:** fresh install / upgrade-with-uploads / iCloud-off device / Files tab flows / BGTask debug trigger.
**Exit:** `grep -r "FeatureFlag.fileSync"` empty; suites + UI tests green; FileSync reachable in a Release-config build.

### A2 — Local-feed episode-identity reconciliation (enabler for item 2; no user-visible change)

Makes it safe for a podcast with server-canonical episode UUIDs to refresh via `LocalFeedRefreshProvider` (today it would re-mint the entire back catalog as hash UUIDs — mass duplication).
1. New `Modules/Sources/PocketCastsServer/Public/LocalFeed/LocalFeedEpisodeMatcher.swift`: pure function `([ParsedFeedItem], existing: [Episode]) → per-item .existing(uuid:) | .new(hashUuid:)`. Match precedence: (1) hash UUID already in DB, (2) exact `downloadUrl` == enclosure URL, (3) title + publishedDate (day granularity). In-memory indexes; `FileLog` line when the fallback fires.
2. `LocalFeedRefreshProvider.swift`: replace `newEpisodes(from:)` (`:82-89`, one `findEpisode(uuid:)` query per item) with fetch-once + matcher (side win: N queries → 1 per podcast).
3. Show-info seeding by resolved UUID: extend `LocalFeedShowInfo.data(from:podcastUuid:)` to take the `[hashUuid: resolvedUuid]` mapping; both seeding sites (`LocalFeedRefreshProvider.swift:53-55`, `LocalPodcastSource.swift:28`) pass it (identity mapping for pure-local podcasts).
4. Documented limitation: item with no guid AND changed enclosure URL AND changed title will duplicate.

**Tests (data-integrity):** cache-seeded podcast + full feed parse → zero new episodes; guid-less feed → enclosure matching; enclosure changed/title+date same → suppressed; genuinely new item → exactly one hash episode, second refresh idempotent; seeded show-info keys matched items under existing UUIDs and `ShowInfoCoordinator` cache-only read succeeds for a server-UUID episode of a `.localFeed` podcast.

### A3 — Signed-out subscribe defaults + route coverage (item 2; depends on A2)

1. `Modules/Sources/PocketCastsServer/Public/ServerPodcastManager.swift`:
   - `addPodcast` (`:244`): `effectiveSource = (refreshSource == .server && subscribe && !SyncManager.isUserLoggedIn() && feedUrlPresent) ? .localFeed : refreshSource` (the `.localFeed → syncStatus=.synced` invariant then applies). Missing feed URL → stays `.server` (`.localFeed` without URL never refreshes — `LocalFeedRefreshProvider.swift:37` skips empties).
   - Subscribe-in-place branch (`:254-259`): signed out → also flip to `.localFeed` + `syncStatus=.synced` (guard non-empty `podcastUrl`).
   - `addLocalFeed` existing-row resubscribe (`:111-122`): signed out → flip `.server` rows to `.localFeed`.
   - Episodes still seed from the cache JSON with canonical server UUIDs; the podcast keeps its canonical UUID (preserves Discover/search subscribed-state and share/deep-link matching) — A2's matcher is what makes subsequent local refreshes safe.
2. Immediate post-subscribe local refresh (closes the show-notes gap): after a signed-out subscribe landing `.localFeed`, call `RefreshManager.shared.refresh(podcast:from:)` (`RefreshManager.swift:57-73`) from `ServerPodcastManager` so all routes inherit it.
3. OPML signed-out fallback: `podcasts/OpmlImporter.swift` after the polling loop (`:172-178`) — unresolvable feed URLs go through `addLocalFeed` regardless of `Settings.localFeedIngestEnabled()` (the General-settings toggle `SJLocalFeedIngestEnabled` keeps its current signed-in semantics).
4. `pktc://subscribe` signed-out fallback: `podcasts/AppDelegate+UrlHandling.swift:240-260` — on `podcastSearch` failure while signed out, `addLocalFeed(feedURL:)` instead of the not-found alert.
5. Transition regression tests (no transition code): sign-in leaves `.localFeed` rows `syncStatus == .synced`, uploads nothing for them; sign-out leaves `.server` rows refreshing via `ServerFeedRefreshProvider`; mixed-library `CompositeFeedRefreshProvider.merged` covered.
6. Docs: sticky-source policy table + signed-out degradations (no AI chapters/transcripts for `.localFeed` — server-generated only; ratings submit prompts login; recommendations no-op).

**Exit:** signed-out fresh install can subscribe from search/onboarding/OPML/`pktc://` (and the future Explore tab via `subscribe(to:)` for free) and receives new episodes with no Pocket Casts refresh dependency; zero duplication in the A2 integration suite over these paths; signed-in behavior byte-identical for `.server` podcasts.

### A4 — Un-gate `upNextSort`, `shareProfile`, `generatedChapters` (item 6; one PR)

Delete cases `FeatureFlag.swift:212,218,221` + defaults `:374-381`. Call sites (keep ON branch): `upNextSort` — `podcasts/UpNextViewController.swift:89,102,103,132,353` (collapse layout-constant ternaries at `:102-103`), `UpNextViewController+Table.swift:40`; `shareProfile` — `PrivacySettingsViewController.swift:37`, `PrivacySettingsDataSource.swift:21,128,141`, `ProfileHeaderView.swift:44`, `SubscriptionProfileImage.swift:10`; `generatedChapters` — `podcasts/Episode Info Coordinator/ShowInfoCoordinator.swift:78` only (do NOT touch `generatedTranscripts` at `:96` — kept, per follow-up answer). Audit rows updated.
**Notes:** `generatedChapters` un-gate = AI chapters for App Store users on server podcasts; silently unavailable for `.localFeed` podcasts (document as expected). `shareProfile` renders signed-out with local data (reads `syncingEmail` only when logged in — QA the signed-out render).

### A5 — Un-gate `voiceBoostN` (item 6; own PR)

1. Delete case `FeatureFlag.swift:182` + default `:354-355`.
2. **The load-bearing second gate:** `Settings.isVoiceBoostNEnabled` (`podcasts/Settings.swift:1422-1426`) — inline to return the stored `audioTuning.voiceBoost.useVoiceBoostN` preference (drop the flag guard). Without this the DSP never engages.
3. `podcasts/GeneralSettingsViewController.swift:18`: show the `.voiceBoostN` row unconditionally.
4. DSP consumers need no changes (all read `Settings.isVoiceBoostNEnabled`): `DefaultPlayer.swift:84` (tap), `EffectsPlayer.swift:97,294` (AtomicBool → `AudioReadTask:399`), `AudioReadTask.swift:37-52,257-283` (`VBN_Process`), `AdvancedAudioSettingsViewModel.swift:29`, `EpisodeLoudnessScanner.swift:27`. Grep-gate that none read the flag directly.
5. **User-facing toggle default stays opt-in (off)** — un-gating makes the toggle visible in all builds; no playback change for users who never enabled it. Users with `useVoiceBoostN` persisted true from TestFlight get VBN on update (intended).
**QA:** A/B listening (off / classic VB / VBN) on speech + music; mid-playback toggle; loudness-scanner path; player unit tests.

### A6 — `newSettingsStorage` / `settingsSync` (scope per user answer — see Final Decisions)

A1–A5 have zero dependency on these flags (paths touched use direct UserDefaults / flag-independent DB state), so both branches are clean:
- **Branch OUT:** nothing to do; `shouldEnableSyncedSettings` stays hard-false (`FeatureFlag.swift:390-392`).
- **Branch IN:** two slices after A3 — **A6a Enable:** flip `shouldEnableSyncedSettings` to `true` (remote keys `new_settings_storage`/`settings_sync` become live kill switches per `:397-400`); zero call-site edits (153 sites take the new-storage path); soak one release; signed-out users exercise only the local `newSettingsStorage` paths — exactly the "storage local always, sync optional" reading. **A6b Delete:** retire both cases; collapse the 153/5 call sites in mechanical per-area PRs (`Settings.swift`, `Podcast.swift:91-121` settings accessors, `SyncTask`); one-time legacy→AppSettings migration audit; remove the `SceneDelegate.swift:199` UI-test override.

## Track B — Data layer (items 3, 26)

**Corrected baseline:** FMDB is fully gone; `executeQuery`/`executeUpdate` are thin GRDB wrappers (`Private/DB/GRDB/GRDBDatabase.swift:19-40`, with a Date→`timeIntervalSince1970` shim). The `grdbQueryInterface` flag is ALREADY deleted (audit doc stale). "Done" is defined by **grep gates**, not counts.

### B0 — Retire `concurrentDatabaseReads` first

ValueObservation depends on stable `DatabasePool` concurrent-read semantics. Delete case + default; unwrap `GRDBQueue.swift:50-53` and `:84-86` (keep `dbPool.read`, delete write-path fallbacks); audit row updated. Marked done in the Track D list to prevent double-work. **Exit:** grep empty; DataModel suite (539 tests) green.

### B1–B4 — Raw SQL → query interface, per-file batches (easy → hard)

Common mechanics per batch: golden parity tests first (seed fixture DB, capture current results; precedent: `AutoAddCandidatesParityTests.swift`), convert via `GRDBQueue+QueryInterface.swift` + `@GRDBRecord` types, delete raw statements, parity green. **Date-semantics guardrail every batch:** converted code must keep `timeIntervalSince1970` column encoding (one round-trip parity assertion per converted table).
- **B1 (warmup):** `Public/NetworkDataUsage/NetworkDataUsageManager.swift` (4), `Private/Managers/UserEpisodeDataManager.swift` (2), stray literals in `DBUtils.swift`/`AutoAddQueueDataManager.swift`.
- **B2:** `Public/Bookmarks/BookmarkDataManager.swift` (5) + `UpNextDataManager.swift` residue (verification + comment cleanup — live grep shows only comments remain).
- **B3:** `Private/Managers/EpisodeDataManager.swift` (3 + the `findEpisodesWhere(customWhere:)`/`findPlaylistEpisodesWhere(query:)` raw executors at `:165,:181` — convert internals to `SQLRequest` now; signatures change in B5) + `PlaylistDataManager.swift` (3).
- **B4:** `Private/Managers/PodcastDataManager.swift` (5–6) + `Public/DataManager.swift` (3 + FileSync journal upserts) + delete `DataHelper.swift` when its last caller converts.
- **Permanent documented residue:** `DatabaseHelper.swift` migrations/DDL (16 sites incl. PRAGMAs) — raw SQL is the correct idiom for migrations.

### B5 — `PlaylistQueryBuilder` → typed GRDB `SQL` literal builders (the hard one)

Not the query interface: its output is dynamic smart-playlist predicate assembly consumed as fragments by 8 consumers; GRDB `SQL` interpolation preserves the composition model with type-safe bindings (kills the `[Any]` argument arrays and rawValue string-splices at `:56,70-73`).
1. Rewrite `Public/PlaylistQueryBuilder.swift`: public API `static func request(...) -> SQLRequest<Episode>` (+ `SQLRequest<Int>` count variant); `removeEmptyFilterGroups` reimplemented on the fragment tree (drops `RegexBuilder`).
2. Migrate consumers: `PlaylistDataManager.swift:61-90`, `DataManager.swift:1063-1088` (then delete string overloads `DataManager.swift:543,551`, `EpisodeDataManager.swift:165,181`); app target: `PlaybackManager.swift:846-847`, `SiriShortcutsManager.swift`, `WidgetHelper.swift`, `PlaylistManager.swift`, `PlaybackIntentActionHandler.swift`, `EpisodesDataManager.swift`; update `EpisodeRepository.swift:20,22,91` + mocks in `PocketCastsDataModelTesting`.
3. Then delete the shim layer: `FMDatabaseQueue+Async.swift`, `executeQuery/executeUpdate` on `PCDatabase`/`GRDBDatabase` (keep minimal `execute(sql:)` for `DatabaseHelper` migrations), `DataManager.count(query:values:)` (`:1262`) + its `DataMaintenance.swift:11` protocol row.
**Parity strategy:** (a) SQL snapshot tests over an `EpisodeFilter` configuration matrix (manual/smart × predicate types × sort × archived × search × `optimizeManualPlaylistQueries` on/off) asserting new SQL+arguments ≡ legacy strings captured as fixtures; (b) result parity on a seeded fixture DB for the same matrix. Legacy builder stays in the test target during transition. Staged: builder + DataModel consumers one PR, app-target consumers next.
**Risk:** this is the app's most behavior-critical SQL (filters, widgets, Siri, autoplay all consume it) — the matrix + staging is the mitigation.
**Track-level exit (grep gates):** `executeQuery\(|executeUpdate\(` matches only `DatabaseHelper.swift`; `FMDatabaseQueue+Async.swift` deleted; no public API takes `(sql: String, arguments: [Any])`; parity suites green; MODERNIZATION.md updated with the DDL-residue note.

### B6 — ValueObservation pilots (item 26; after B0)

**Pilots: (P1) podcast grid, (P2) filter unplayed counts + app badge. NOT Up Next** (playback interplay; prime typed-notification territory — avoid double-migrating).
1. New `Public/Repositories/DatabaseObserving.swift`: `observeHomeGrid() -> AsyncStream<HomeGridSnapshot>`, `observePlaylistUnplayedCounts() -> AsyncStream<[String: Int]>`, `observeBadgeCount(...) -> AsyncStream<Int>`. `DataManager` implements via `ValueObservation.tracking { ... }.removeDuplicates()` bridged from `observation.values(in: dbPool)`; `DependencyKey` `\.databaseObserver` in `Repositories+Dependency.swift` (testValue mirrors liveValue per file convention) + yielding mock in `PocketCastsDataModelTesting`.
2. MainActor delivery: consumers own `Task { for await value in stream { apply(value) } }` (app target is MainActor-default-isolated); cancel on disappear/deinit.
3. **P1** `podcasts/Podcasts/All Podcasts/PodcastListViewController.swift`: replace the nine DB-derived observers at `:130-141` (`podcastsRefreshed, podcastAdded, podcastDeleted, opmlImportCompleted, syncCompleted, episodeArchiveStatusChanged, episodePlayStatusChanged, folderChanged, folderDeleted`) with `observeHomeGrid()`; keep non-DB observers (tab tap, search, playback if actually rendered). Posts stay for other consumers.
4. **P2** `podcasts/PlaylistsViewController.swift` (cell unplayed counts) + `podcasts/Utilities/BadgeHelper.swift` (replace polled `updateBadge()` from `AppDelegate.swift:176,288`; keep one explicit call for BG-task paths with no run loop).
**Interplay rule (recorded for Track C):** P1/P2 screens are owned by this track and excluded from notification migration for DB-derived events; notifications stay authoritative for non-DB events everywhere; ownership table (screen × event source) in the B6 PR description.
**Risks:** observation storms during bulk refresh writes (mitigate: `removeDuplicates`, consumer-side throttle); task-lifecycle leaks (cancellation audit). Perf check on a 500-podcast fixture.
**Exit:** both pilots fully observation-driven for DB state with their DB-derived `addCustomObserver` lines deleted; no grid-latency regression; pattern documented so later screens adopt mechanically.

---

## Cross-track sequencing

- **Wave 1 (parallel):** A1, A4, A5 · B0, B1 · D1 batches · H1, H6, H7 · I3 · J1–J3 (docs) · F4, F5.
- **Wave 2:** A2 → A3 · B2–B4 · C Phase 4 spike · D2 playback batches (E3's flag with E3) · E1, E2, E3 · F1, F2 · H2–H4 · I1.
- **Wave 3:** B5 → B6 · C Phase 5 sweeps (respecting B6 ownership rule) · F3 · G1–G3 · H5 · I2 · C Phase 6 cleanup last.
- Flag deletions (A1/A4/A5/B0/D batches) each update `docs/FeatureFlagAudit.md` in the same PR to keep the register authoritative.

## Verification (program-wide)

- Every PR: `mise run build:staging`, `mise run test:staging`, `mise run check:static`, `mise run check:concurrency` (baseline stays empty), plus the crash-report sweep + `smoke:launch` already wired into CI.
- Track A: A2/A3 integration suites (duplication-zero invariants) + signed-out end-to-end manual pass (fresh install, subscribe via search/OPML/pktc, refresh, play, Files tab, FileSync via iCloud).
- Track B: parity suites per batch; B5 SQL-snapshot matrix; B6 500-podcast perf fixture.
- Track D: playback QA checklist per batch (play/pause/seek/route change/stream/download/Up Next).
- Track E/F/G: feature QA per slice + new themed snapshots (H2) for every new SwiftUI view; `mise run test:tsan` after E1/E3 (audio-thread changes) and F1.
- UI tests: `mise run test:smoke-ui` after A1 (Files screens), F1 (Live Activity glue), G2 (new tab).

## Final scope decisions — PROVISIONAL (interactive question UI failed twice on 2026-07-12; recommended defaults adopted, awaiting user confirmation at plan review)

1. **A6 scope — PROVISIONAL: Branch IN (A6a + A6b).** Item 6's wording ("storage local always, sync optionally when signed in") maps exactly onto the parked `newSettingsStorage` (153 call sites — new structured local AppSettings storage) / `settingsSync` (5 sites — server sync of those settings when signed in) flags, currently hard-disabled via `shouldEnableSyncedSettings = false` (`FeatureFlag.swift:390-392`). Plan of record: **A6a** flip `shouldEnableSyncedSettings` to `true` (remote keys `new_settings_storage`/`settings_sync` become live kill switches), soak one release; **A6b** delete both cases and collapse call sites in per-area PRs. *If the user says no: skip A6 entirely (Branch OUT) — A1–A5 are unaffected by design. If "enable only": do A6a, move A6b to `docs/DeferredWork.md`.*
2. **F3 Siri phrasing — PROVISIONAL: full SiriKit deletion.** Delete `PodcastsIntents`/`PodcastsIntentsUI` targets, `SJ*` generated intents, `SiriShortcutsManager` donations; ship `PodcastAppEntity` + parameterized `PlayPodcastIntent` as the replacement; accept that free-form "Play *<podcast name>*" utterance matching may degrade vs `INPlayMediaIntent` + `SiriPodcastSearchManager`. *If the user prefers: keep a slimmed `PodcastsIntents` extension handling only `INPlayMediaIntent` (delete everything else) — F3 steps 1–2 are identical either way; only the final target deletion differs.*
