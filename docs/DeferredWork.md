# Deferred Work Register

The consolidated record of every item the 2026-07-12 program review (see
`plans/Pocket Casts iOS — Local-First & Product Modernization Program.md`, Decision Register)
deferred rather than scheduled or rejected. One section per item: why it was deferred, current
state (metrics re-verified 2026-07-12), and a concrete re-entry plan.

Items the review rejected outright (SKIP/NO) are recorded only in the program plan's Decision
Register, not here.

---

## Item 7 — DI call-site conversion

**Why deferred:** mechanical, large, and low-risk-low-reward relative to the program's feature
work; the repository-protocol seams from MODERNIZATION.md Phase 2 already exist for new code.

**Current state:** `DataManager.sharedManager` ~454 sites / 134 files;
`PlaybackManager.shared` ~390 / 71 (engine/player-callback files stay on the singleton by
design); `Theme.sharedTheme` ~276 / 69 (many are `environmentObject(Theme.sharedTheme)` injection
sites that should NOT convert).

**Re-entry:** follow the `PlaylistsViewController` / `ArchiveHelper` conversion template
(`@Dependency`-injected repository protocols, mocks from `Modules/Sources/PocketCastsDataModelTesting/`).
Known seam gaps to close first: `activateAudioSession` missing from `PlaybackManaging`;
`DataManager+FileSync` surface has no repository protocol. Convert file-by-file with behavior-free
diffs; each PR deletes its file from a burn-down list.

## Item 8 — Oversized view-controller splits

**Why deferred:** high-churn files; splitting mid-program would conflict with Tracks C/E/G touching
the same code.

**Current state:** `PlaybackManager.swift` 2,683 · `PodcastViewController.swift` 1,743 ·
`Settings.swift` 1,609 · `TranscriptViewController.swift` 1,372 · `MainTabBarController.swift` 920.
The original Phase-2 exit criterion (no non-playback file > 1,000 lines) remains unmet.

**Re-entry:** after Track C (typed notifications) and G1 (transcript reader) land, split in this
order: `Settings.swift` (pure accessor groups → extensions in files), `PodcastViewController`
(list/data-source/actions), `TranscriptViewController` (highlight engine is shared with the reader
by then), `PlaybackManager` last (needs the E-track features stable).

## Item 14 — Adaptive effects switching (music/speech auto-profiles)

**Concept:** auto-suspend trim-silence and voice boost during music segments using the existing
SoundAnalysis VAD discriminator (`podcasts/AdvancedAudio/TrimSilenceDetector.swift` — the system
VAD mode with retrospective veto). Entry point: `AudioReadTask` already consults the detector
per-buffer; an "effects profile" toggle would swap `AudioTuning` snapshots when the
music/speech classification is stable for N seconds.

**Re-entry:** configurable, default off, in the user settings; measure false-positive rate on music-heavy shows
before any UI.

## Item 19 — FoundationModels episode intelligence

**Concept:** on-device summaries ("catch me up" for partially-played episodes), chapter-title
generation for chapterless episodes (UX slot already exists: `generatedChapters`, un-gated in
Track A4). Storage would mirror the transcription artifacts (device-local, no sync).

**Re-entry:** user option to use Apple's `FoundationModels` summarization over VTT
cue text; measure quality/latency per device class before productizing.

## Item 24 — `ObservableObject` → `@Observable` migration

**Why deferred:** mechanical; zero user value; conflicts with any track touching view models.

**Current state:** ~160 `@Published` / ~54 `ObservableObject` conformances / 1 `@Observable`
(`AdvancedAudioSettingsViewModel`, migrated 2026-07-11 as the pattern-setter).

**Re-entry:** use `AdvancedAudioSettingsViewModel` as the template (notably: `@Observable` supports
`didSet` on stored properties; `@ObservationIgnored` for non-state; `@Bindable` at use sites;
`environmentObject` → `environment` where Theme is involved must be coordinated with the theme
system). Convert leaf view models first; `Theme` itself last (69 files inject it).

## Item 33 — Coverage floor raise + coverage upload

**Why deferred:** the floor mechanism exists and works; raising it is blocked on writing the item-35
tests, and external upload needs an account decision.

**Current state:** floor 2.0 in `scripts/ci/coverage-floor.txt` (real aggregate ~15% per its
comment; app target ~3.7%). Slather output is terminal-only in the Danger job; SonarCloud
(`sonar-project.properties`) has no coverage wired.

**Re-entry:** after each Track H/G test wave, ratchet the floor to (current − 0.5). For upload:
either `sonar.coverageReportPaths` from the Slather Cobertura output, or drop SonarCloud coverage
and rely on the floor + Danger table.

## Item 35 — Tests for untested feature areas

**Why deferred:** wholesale VC testing needs the DI conversion (item 7) to make construction cheap;
the program prioritizes tests around code it *changes*.

**Current state (untested areas):** Player UIKit stack (~40 files), Onboarding (34), Settings VCs,
New Detail (26), Sharing UI (21).

**Re-entry lever:** repository protocols + `@Dependency` mocks
(`Modules/Sources/PocketCastsDataModelTesting/`); themed snapshot coverage (H2 helper) gives the
cheapest first coverage for SwiftUI portions; VC logic tests follow DI conversion per area.

## Item 39 — Performance regression tests

**Concept:** XCTMetric baselines for cold start (`XCTApplicationLaunchMetric`), database migrations
(production fixtures already exist: `ProductionDatabaseMigrationFixtureTests.swift`), and
large-library grid scroll (`XCTOSSignpostMetric`).

**Re-entry:** land baselines as *reporting-only* first (Danger table of deltas), enforce after
variance is characterized (~2 weeks of runs).

## Item 50 — Extract features into SPM modules

**Why deferred:** depends on items 7 (DI) and 49 (file organization) to be tractable.

**Candidates (in extraction order):** Bookmarks (cleanest boundaries), Analytics adapters,
Sharing, Onboarding. `PocketCastsFileSync` is the extraction template (protocol-injected app
dependencies, no UIKit in module).

## Item 55 — Small-stuff sweep (with the specific inventory)

**TODO/FIXME inventory (19 sites, re-verified):** notable ones —
`OptionsPicker.swift:51` (layout mystery), `UserEpisodeDetailViewController.swift:106`
(force-unwrap TODO), `TopShadowView.swift:15` (theme-blind shadow color),
`PlayerContainerViewController.swift:169/209/268` ("Show install banner" ×3 — decide feature or
delete), `AppTheme.swift:538` (inelegant lookup), `FolderViewController.swift:251` (diffable
data source), `AddCustomViewController.swift:222` (error copy), missing-analytics TODOs at
`ManualPlaylistsChooserViewController.swift:328/337`, `PlaylistsViewController+Table.swift:237`,
`PodcastViewController.swift:1413`, `IncomingShareListViewController.swift:156` (empty TODO),
`DownloadManager+URLSessionDelegate.swift:17`, `NowPlayingPlayerItemViewController.swift:404`
(install prompt), `UploadedViewController.swift:168` (table diff), `ArchiveHelper.swift:25`
(literal "TODO" string returned!), `DefaultPlayer.swift:891` (`TODO(A2d)` — tracked separately,
needs on-device TSan).

**Also:** ~28 stray `print(` calls to route through `FileLog`; ~60 commented-out code lines to
delete or justify.

**Re-entry:**  cleanup PR  (TODOs triaged to fix/delete/issue; prints; dead
code). `ArchiveHelper.swift:25` should be fixed on sight next time that file is touched.

## Item 57 — Podping / WebSub instant feed updates

**Why deferred:** Track A's polling refresh must ship and soak first; instant-update plumbing is an
optimization on top.

**Concept:** subscribe to Podping (podcast-index socket/relay) for followed feeds with
`refreshSource == .localFeed`; on ping, trigger `RefreshManager.refresh(podcast:)` for just that
podcast. WebSub as fallback for feeds advertising hubs.

**Re-entry:** after A2/A3 soak. Needs a battery/socket strategy decision (BGAppRefresh polling of a
relay vs push-via-server is likely the realistic iOS answer).

## Item 67 — Shake-to-report in beta

**Concept:** extend `podcasts/BackgroundShakeObserver.swift` (exists — currently sleep-timer
restart) to present a feedback sheet in TestFlight builds, attaching the bitdrift session ID and
recent `FileLog` tail into `SupportFeedbackRequest`.

**Re-entry:** after F4; gate to `BuildEnvironment.current == .testFlight`.

## A6b — Delete `newSettingsStorage`/`settingsSync` and collapse call sites

**Why deferred:** A6a flipped `shouldEnableSyncedSettings` to `true` on 2026-07-12 (remote keys
`new_settings_storage`/`settings_sync` are live kill switches). The flags themselves must soak one
release before deletion.

**Concept:** retire both `FeatureFlag` cases; collapse the ~153 `newSettingsStorage` call sites
(`Settings.swift`, `Podcast.swift` settings accessors) and 5 `settingsSync` sites (`SyncTask`) in
mechanical per-area PRs; one-time legacy→AppSettings migration audit; remove the
`SceneDelegate` UI-test override for the flag.

**Re-entry:** one release after A6a ships with no kill-switch activation.

## Item 1 — Download-triggered background transcript indexing

v1 indexes transcripts when viewed; auto-transcribe-on-download exists for the *generated* corpus only.
This app must have complete and comprehensive transcription and indexing.

**Unify two transcript-search surfaces** — generated transcripts search from Profile (`TranscriptionSegmentFTS`), viewed podcast transcripts from New Search (`TranscriptCueIndex`). Unifying them into one surface (and one corpus policy)

## Item 2 — Auto-chapterization based on the transcript

Requires an API key for LLM's to call or use Apple's Foundation models, or a backend call (update proto and server spec), user selectable

## Item 3 — Chapter image support with progressive image changes in Apple AV

 `image` is decoded and stored; no UI yet.
