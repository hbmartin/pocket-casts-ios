# Deferred Work Register

The consolidated record of every item the 2026-07-12 program review (see
`plans/old/Pocket Casts iOS — Local-First & Product Modernization Program.md`, Decision Register)
deferred rather than scheduled or rejected, updated for the 2026-07-13 deferred-work program
that shipped seven of them. One section per still-deferred item: why it was deferred, current
state, and a concrete re-entry plan.

Items the review rejected outright (SKIP/NO) are recorded only in the program plan's Decision
Register, not here.

---

## Shipped by the 2026-07-13 deferred-work program

| Item | Outcome | PRs |
|---|---|---|
| **1 — Complete transcript indexing + unified search** | One FTS5 corpus (`TranscriptSegmentIndex`, migration 82) with a `source` column; download-triggered acquisition (feed-provided transcript first, generation as fallback); transcription **always on** with consent-gated remote auto-run and a per-podcast on-device-only opt-out; battery policy picker for local jobs; New Search is the sole surface (Profile screen retired); 200 MB byte cap with provided-only eviction. Decisions that changed the register's premises: **no backfill** of existing downloads (organic completion), remote providers **are** auto-run once consented. | #275 #276 #277 |
| **3 — Chapter images** | Chapter-list thumbnails; Podcast Index/Podlove artwork URLs captured and lazily fetched into every artwork sink; progressive `AVPlayerItemMetadataOutput` fills gaps mid-stream and grows synthetic chapters for chapterless streams. (The register's "no UI yet" was stale — player/mini/lock-screen art already worked.) | #279 |
| **19 — FoundationModels episode intelligence** | Catch Me Up (tail-weighted recap of the played portion; player shelf action + summary-card button, flag `catchMeUp`) and on-device chapter generation from the local transcript at lowest precedence (flag `onDeviceChapters`, cached per episode) — the latter completes **Item 2's on-device path**. | #280 |
| **14 — Adaptive effects switching** | Full mechanism shipped **default off** with FileLog switch telemetry per the measure-first mandate: "music" class read from the existing classifier pass, hysteresis segment classifier, trim + Voice Boost suspended during music as a runtime override (tuning blob untouched). Toggle in Advanced Audio. Flip the default only after reviewing `[AdaptiveEffects]` logs on music-heavy shows. | #281 |
| **55 — Small-stuff sweep** | Every TODO fixed or tracked: trivial ones fixed on sight (incl. `ArchiveHelper`'s user-visible literal "TODO"), non-trivial ones became issues #282–#286, production `print()` routed through FileLog with a Semgrep rule (`no-bare-print`) keeping it that way. Only `TODO(A2d)` remains, deliberately. | #287 |
| **39 — Performance regression tests** | Reporting-only baselines per the re-entry plan, scoped to cold start + podcast-page entry + episode-card entry (no scrolling): `PerformanceUITests` plan on the seeded scenario, nightly `perf-ui` job, `perf-report.rb` delta table vs `scripts/ci/perf-baselines.json`. Record baselines after ~2 weeks of runs, then consider gating. | #288 |
| **67 — Shake-to-report** | Shake in debug/TestFlight builds opens a feedback sheet posting to the fork's own endpoint with structured diagnostics (`Api_SupportFeedbackRequest` fields 6–9: logs tail, bitdrift session ID, device info, app version). New `BuildEnvironment.testFlight` (sandbox receipt; also enables beta flags on TestFlight), bitdrift extended to TestFlight, `FileLog.tailOfLogFile`. Sleep-timer restart keeps the shake while a timer runs. Backend half: podcast-backend#10. | #290 |
| *(infra)* Auto-format fix | `redundant_nil_coalescing` autocorrect removed (it stripped a semantic `?? nil` and shipped a real bug) + Semgrep guard for nil-checks on `dbQueue.read/write` results. | #278 |

Item 57 (Podping) was deliberately skipped this round — see below.

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

## Item 24 — `ObservableObject` → `@Observable` migration

**Why deferred:** mechanical; zero user value; conflicts with any track touching view models.

**Current state:** ~160 `@Published` / ~54 `ObservableObject` conformances / 1 `@Observable`
(`AdvancedAudioSettingsViewModel`, migrated 2026-07-11 as the pattern-setter). The deferred-work
program added new `ObservableObject`s (`CatchMeUpViewModel`, `EpisodeSummaryViewModel` extensions)
that should ride along when this converts.

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
New Detail (26), Sharing UI (21). The deferred-work program added seams worth reusing: injected
coordinator/queue closures (`TranscriptAcquisitionCoordinator`, `TranscriptionQueueManager`'s
`powerState`), pure decision types (`TranscriptAcquisitionDecision`, `MusicSegmentClassifier`,
`TranscriptionBatteryPolicy`) that show the extract-and-test pattern.

**Re-entry lever:** repository protocols + `@Dependency` mocks
(`Modules/Sources/PocketCastsDataModelTesting/`); themed snapshot coverage (H2 helper) gives the
cheapest first coverage for SwiftUI portions; VC logic tests follow DI conversion per area.

## Item 50 — Extract features into SPM modules

**Why deferred:** depends on items 7 (DI) and 49 (file organization) to be tractable.

**Candidates (in extraction order):** Bookmarks (cleanest boundaries), Analytics adapters,
Sharing, Onboarding. `PocketCastsFileSync` is the extraction template (protocol-injected app
dependencies, no UIKit in module).

## Item 57 — Podping / WebSub instant feed updates

**Why deferred:** Track A's polling refresh must ship and soak first; instant-update plumbing is an
optimization on top. Deliberately skipped by the 2026-07-13 program (a draft plan exists at
`plans/podping.md`).

**Concept:** subscribe to Podping (podcast-index socket/relay) for followed feeds with
`refreshSource == .localFeed`; on ping, trigger `RefreshManager.refresh(podcast:)` for just that
podcast. WebSub as fallback for feeds advertising hubs.

**Re-entry:** after A2/A3 soak. Needs a battery/socket strategy decision (BGAppRefresh polling of a
relay vs push-via-server is likely the realistic iOS answer).

## A6b — Delete `newSettingsStorage`/`settingsSync` and collapse call sites

**Why deferred:** A6a flipped `shouldEnableSyncedSettings` to `true` on 2026-07-12 (remote keys
`new_settings_storage`/`settings_sync` are live kill switches). The flags themselves must soak one
release before deletion.

**Concept:** retire both `FeatureFlag` cases; collapse the ~153 `newSettingsStorage` call sites
(`Settings.swift`, `Podcast.swift` settings accessors) and 5 `settingsSync` sites (`SyncTask`) in
mechanical per-area PRs; one-time legacy→AppSettings migration audit; remove the
`SceneDelegate` UI-test override for the flag.

**Re-entry:** one release after A6a ships with no kill-switch activation.

## Item 2 — Auto-chapterization (backend variant)

The on-device path shipped with Item 19 (#280, flag `onDeviceChapters`). What remains deferred is
the backend/API-key variant: a server-side chapterization call (proto + server spec update,
user-selectable provider), worth revisiting only if on-device quality disappoints on longer
episodes or older devices.
