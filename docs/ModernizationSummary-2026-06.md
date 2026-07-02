# Pocket Casts iOS Modernization — June 2026 Summary & Roadmap

Eleven slices plus coverage tooling shipped as a stacked PR chain (**#72 → #101**, merge in order),
with Phase 3 record migration now in progress on a follow-on branch. Every slice was verified before
commit with the full test suite (`mise run test:staging`), static checks (`mise run check:static`),
and the new concurrency gate (`mise run check:concurrency`).

**Headline metric:** the strict-concurrency warning baseline went from **74 entries at creation to
13**, and a CI ratchet guarantees it can only shrink. The remaining 13 were all design-gated on the
DataManager/record Sendability decision (Phase 3), not mechanical fixes. _(Update 2026-07-01: with the
Phase 3 leaf records landed, a follow-on slice cleared the 10 non-playback entries — `ListEpisode`
honest-`Sendable`, `ImageManager.podcastUrl` → `static`, and `@MainActor` on `ShareProfileViewModel` /
`PlaylistDetailViewModel` — taking the ratchet to **3**, the permanent `DefaultPlayer`/`PlaybackManager`
playback floor. See [Phase3-RecordSendability.md](Phase3-RecordSendability.md).)_ _(Update 2026-07-02,
slice 18: DI is now a single system — the seven repository `DependencyKey`s moved to swift-dependencies
and the homegrown `PocketCastsDependencyInjection` module was deleted. The repository protocols are
`Sendable`, with `DataManager` `@unchecked Sendable` behind a documented delegation contract.)_

## Starting state

The repo was sharply bifurcated. The SPM modules (`Modules/`, ~48K lines) were already modern:
strict concurrency enforced at zero warnings, async-first APIs, a dependency-injection container,
GRDB macros. The main app (`podcasts/`, ~121K lines) was 3–4 years behind: Swift 5 language mode
with no concurrency checking, ~507 completion-handler signatures, 1,000+ GCD calls, a singleton web
(`DataManager.sharedManager`, `PlaybackManager.shared`, `Settings`, …) with the DI module almost
unused (~3 adopters), ~168 raw-SQL sites behind a default-on `grdbQueryInterface` flag, and 67
accumulated feature flags.

Three scoping decisions shaped everything: prioritize **concurrency**, **architecture/DI**, and
**data layer + cleanup**; defer the **playback engine** (highest risk, hardest to test); exclude
**UIKit → SwiftUI screen migration** entirely.

## What shipped, and why

### Slice 1 — Concurrency ratchet + roadmap (PR #72)

`MODERNIZATION.md` (the living roadmap), `SWIFT_STRICT_CONCURRENCY = targeted` for the app target,
and a rewrite of `scripts/ci/check-concurrency-warnings.sh` into a **deletion-only baseline
ratchet**: any first-party concurrency warning not in `scripts/ci/concurrency-baseline.txt` fails
CI; entries may only ever be removed. Plus `mise run concurrency:baseline` (regeneration from a
clean `build-for-testing`), shell tests for the gate, and a Semgrep rule requiring a justification
comment on every `nonisolated(unsafe)`.

**Reasoning.** Of the candidate first moves (DI pilot, flag retirement, Objective-C ports), only
this one was deterministically completable and *foundational*: every later slice burns the baseline
down, and the ratchet prevents regression while that happens. `targeted` mode was the right dial —
it only checks code that already adopts concurrency, so it surfaced a tractable 57 app warnings
instead of a complete-mode avalanche. The other candidates were rejected for cause: flag retirement
isn't unilaterally decidable (every flag has a live remote kill-switch key), and the ObjC ports net
zero bridging-header shrinkage (`catchException` cannot be expressed in Swift).

Two discoveries made the design better than planned: (a) the existing "zero warnings under
Modules/Sources" CI invariant was fictional — clean builds surfaced 6 module warnings that CI's
incremental DerivedData never recompiles — so the ratchet became one unified baseline instead of
two tiers; (b) CI gates on the *test* build log, so the baseline and its regeneration task cover
test targets too.

### Slice 2 — DI seams for FileLog and DownloadManager (PR #73)

`FileLogging` and `DownloadManaging` protocols covering exactly the surface call sites use today,
registered in the container as `\.fileLog` and `\.downloadManager` with the production singletons
as defaults; pilot `@Dependency` adoption in `LogsViewModel` and `DownloadsViewController`; tests
proving each key can be overridden with a mock — the first mock-based tests these singletons ever had.

**Reasoning.** The DI module existed but was unproven beyond playlists. Starting with FileLog
(small, stable surface) and DownloadManager (small *consumed* surface, ~14 members) established the
seam pattern cheaply. Doing this *after* the ratchet mattered: the new `DependencyKey`s had to be
born concurrency-clean (justified `nonisolated(unsafe)`, enforced by the slice-1 Semgrep rule)
instead of multiplying unchecked global state.

### Slice 3 — Modules to zero (PR #74)

Fixed all 17 module and test-target baseline entries: `EpisodeDataManager`/`UserEpisodeDataManager`
became compiler-verified `Sendable` final classes; `SchemaMigration` became `Sendable` with a
`@Sendable` migrate closure; lock-guarded statics got justified `nonisolated(unsafe)`;
`runOffMainThread` documents its single cross-thread transfer; test files got `@MainActor` and
Sendable fixtures.

**Reasoning.** Restoring the modules' zero-warning invariant *for real* (it had been an
incremental-build artifact) gives the strongest possible foundation: all data-layer and server code
is now genuinely clean, so app-side burn-down never chases moving targets in its dependencies.

### Slice 4 — Feature-flag audit (PR #75)

`docs/FeatureFlagAudit.md`: all 71 flags with default value, call-site count, representative files,
retirement assessment, and an empty sign-off column. Headline: 4 flags are completely dead (zero
call sites), ~36 are retirement candidates, 18 are playback-adjacent and deferred regardless.

**Reasoning.** Generated deterministically by script from the actual definitions and call sites, not
by judgment. Deliberately ships *no removals*: nearly every flag's `remoteKey` is a live remote
kill-switch, so each retirement needs sign-off from whoever owns remote config. The audit converts a
fuzzy "retire old flags" goal into a reviewable checklist.

### Slices 5–8 — App-target burn-down batches (PRs #76–#79)

Four batches, grouped by fix *shape* so each PR is mechanically reviewable:

- **#76 — `@MainActor` view models** (`LogsViewModel`, `ManageDownloadsModel`,
  `RecommendationsViewModel`, `PlaylistCellViewModel`, `PodcastRatingViewModel`,
  `SyncSigninViewModel`) plus the collateral annotations the compiler then required
  (`LoginCoordinator` methods, `ForgotPasswordDelegate`, `InterestsView` callbacks). The governing
  rule, applied per file: *a view model only gets `@MainActor` if its tasks don't do synchronous
  heavy work* — `ManageDownloadsModel` switched to `Task.detached` for its disk scan, and
  `RatePodcastViewModel` was deliberately **deferred** because its load path makes synchronous
  DataManager calls that the annotation would move onto the main thread.
- **#77 — Sendable value types**: `EpisodeSearchResult`, `PodcastFolderSearchResult`,
  `PodcastIndexEvelope`, `Episode.Metadata` (+nested types). All compiler-verified, no
  `@unchecked`. Cheapest slice of the session: 4 type annotations cleared 17 baseline entries,
  because the warnings were actor-crossings of types that simply lacked the conformance.
- **#78 — isolation hops**: completion handlers that touched main-actor UI now hop explicitly via
  `Task { @MainActor in … }` instead of unverifiable `DispatchQueue.main.async` conventions;
  `ShiftyLoadingAlert` became `@MainActor` (the compiler confirmed all 23 call sites were already
  main-actor contexts); a pure mapping function became `nonisolated`.
- **#79 — sharing/feed cleanup**: `PodcastList`/`ListPodcast` Sendable, two more `@MainActor` view
  models, a documented `UnsafeTransfer` hand-off in `VideoExporter`, and deletion of the unused
  `View.itemProvider()` extension (dead code that carried one of the warnings).

**Reasoning.** Burn-down ordered easiest-verifiable-first: pure annotations → type conformances →
control-flow restructuring. Each batch ran the full suite plus a clean ratchet pass on the test
log, and anything that risked a behavior change (main-thread DB work, weak-self semantics in a
fire-and-forget closure) was either restructured to preserve behavior or explicitly deferred.

### Slice 9 — AVAsset + RatePodcastViewModel burn-down (PR #97)

Sharing-domain `AVAsset` property access moved to `@preconcurrency` import (baseline 17 → 14), then
`RatePodcastViewModel` got `@MainActor` *without* moving its DataManager calls onto the main thread —
the load path was first restructured so the annotation was safe (baseline 14 → 13). The
record-Sendability decision was explicitly **deferred to Phase 3, driven by GRDB 7**, rather than
ratified locally.

**Reasoning.** This is where the mechanically-fixable baseline bottomed out. The remaining 13 entries
(`PlaylistDetailViewModel`, `PlaylistMetadataLoader`/`ListEpisode`, `ShareProfileViewModel`, plus the
permanent `DefaultPlayer`/`PlaybackManager` playback entries) all require the DataManager/record
Sendability contract to be settled first — so the burn-down correctly stops here and hands off to
Phase 3 rather than forcing `@unchecked Sendable` band-aids.

### Slice 10 — swift-dependencies adoption (PR #98)

Replaced the homegrown `PocketCastsDependencyInjection` container for the Sendable DI keys with
pointfree [swift-dependencies](https://github.com/pointfreeco/swift-dependencies): `\.fileLog`,
`\.downloadManager`, and the playlist-metadata keys now use `DependencyKey`
(`liveValue`/`testValue`), task-local `DependencyValues`, and scoped `withDependencies` overrides —
removing the global mutable `static var currentValue` that was itself a concurrency smell. Call-site
`@Dependency(\.key)` syntax is unchanged, so adoption was an import swap. The seven non-Sendable
repository keys stay on the homegrown container until the Phase 3 record work lands.

**Reasoning.** The DI substrate had to become concurrency-aware *before* mass call-site adoption, so
each future `@Dependency` site inherits `Sendable` `DependencyValues` rather than re-touching it later.

### Slice 11 — Phase 3 scoping + Folder → struct record (PRs #99, #100)

Opened Phase 3 with `docs/Phase3-RecordSendability.md` (the GRDB-7 struct-migration strategy) and
proved the path on the smallest record: `Folder` became `struct Folder: Identifiable, Equatable,
Sendable` (was an `@objc` active-record `NSObject`), exercising the `@GRDBRecord` macro's struct path
end-to-end in the real DB layer for the first time. The value-type switch forced the reference-semantics
fixes it should: `save(folder:)` returns the saved copy instead of back-mutating its argument, and
call sites (`createFolder`, `FolderHelper`, `SyncTask`, `PodcastListViewController.saveSortOrder`,
`HomeGridDataHelper`) consume the return. Validated green: DataModel 448, Server 40, app 259, 0
failures. The companion commit surveyed **EpisodeFilter** (record 2 of 5) — ~80 mutation sites, ~40
back-mutating save callers, `Set<EpisodeFilter>` with inconsistent `isEqual`/`hash`, `@objc`/KVC XIB
runtime risk, 200+ test instances — and sized it as its own multi-session effort.

**Reasoning.** Migrating the trivial record first de-risks the macro and tooling before the heavy
records (`EpisodeFilter`/`Podcast`/`Episode`/`UserEpisode`), where the Strategy B (struct) vs
confine-and-snapshot tradeoff is still open and explicitly flagged for revisiting.

### Coverage tooling (PR #101)

Added Slather + Danger reporting (`danger-slather`, `danger-xcode_summary`, `danger-xcprofiler`) with
conservative report-only defaults, and enabled code coverage on the staging test scheme. Baseline
coverage is ~15% overall (~3.7% for the app target) — instrumentation only; no enforcement gate yet.

## Why this sequencing

1. **Ratchet before everything** — otherwise each improvement can silently regress while later work
   proceeds, and new code (like DI keys) isn't held to the new standard.
2. **DI before complete-mode concurrency** — under `complete` checking, the ~711 `.shared` call
   sites are the largest error class. Injecting first means each singleton's isolation gets decided
   once, at its `DependencyKey`, instead of touching every call site twice.
3. **Modules before app** — burn the dependency layer to zero so app fixes never chase warnings
   originating below them.
4. **Audit before retirement** — flag removal is a sign-off workflow, not a code change; the audit
   table is the artifact that unblocks it.
5. **Playback last, always** — every slice explicitly routed around `PlaybackManager`,
   `DefaultPlayer`, and the audio pipeline; their baseline entries are intentionally permanent until
   Phase 5.

## Roadmap for future phases

Current ratchet state: **3 baseline entries** (down from 13 on 2026-07-01), all in the permanent
`DefaultPlayer`/`PlaybackManager` playback subsystem deferred to Phase 5. The full phase definitions
live in `MODERNIZATION.md`; this is the forward plan with what each step is waiting on.

### Near-term slices (no new design needed, in rough order)

0. **Repo-health fix first (found 2026-07-02):** two DataModel tests fail on trunk independently of
   modernization work — `DatabaseHelperBaselineTests` still asserts schema version 73 after upstream
   merge #4427 added migration 74, and
   `testUpdateAutoAddToUpNextUpdatesNewSettingsStoragePayloadFromEmptySettings` fails its
   "marked unsynced" assertions from the recent `newSettingsStorage` work. Fix in a standalone PR so
   every later slice validates against a green base. (Also: the PR #128 test fix lives on
   `pr-128-followups`, which must land for the app test target to compile.)
1. **DI call-site adoption batches** — migrate remaining `FileLog.shared` (~640 sites) and
   `DownloadManager.shared` (~110 sites) call sites to `@Dependency`, grouped by feature area.
   Mechanical now that the seams exist and everything is on one substrate: slice 18 (2026-07-02) moved
   the seven repository `DependencyKey`s to swift-dependencies and **deleted the homegrown
   `PocketCastsDependencyInjection` container**. New consumers of `DataManager` surface area should
   inject `@Dependency(\.episodeRepository)` etc. rather than reaching for `sharedManager`
   (`ArchiveHelper`/`PlaybackTimeHelper` are the adoption template).
2. **Flag retirement, candidate batches** — the 4 dead (zero-call-site) flags were removed 2026-06-27
   (`guestListsNetworkHighlightsRedesign`, `refreshPlaylistOnSubscriptions`, `smartCategories`,
   `syncStats`; 71 → 67 cases). The ~36 live candidates are still *waiting on* remote-config sign-off
   recorded in `docs/FeatureFlagAudit.md` (only the 4 dead sign-offs filled so far — the remaining Phase
   0 exit criterion). Retire in batches of 3–5, one PR per batch.
3. **Phase 3, outstanding thread: raw SQL → GRDB query interface** — the record-Sendability sub-effort
   is **done** (`Folder`/`EpisodeFilter`/`Podcast` shipped as `Sendable` structs; `Episode`/`UserEpisode`
   reclassified to Phase 5; slice 17 cleared the 10 gated baseline entries, ratchet 13 → 3). What
   remains is converting the ~168 raw-SQL sites in `PocketCastsDataModel` one DAO/table per PR with
   parity tests, then **deleting the `grdbQueryInterface` flag and legacy paths** (see the Phase 3
   section below).

> The slice-9 **AVAsset** sharing-domain migration is **done** (`@preconcurrency`); the only
> remaining `AVAsset` baseline entry is in `DefaultPlayer` and is intentionally deferred to Phase 5.

### Phase 2 — DI completion & decomposition (medium risk, ~20–35 PRs)

- **Settings/ServerSettings facades**: these are static-API namespaces, not instance singletons, so
  the seam needs design — split the 1,595-line `Settings` into focused protocol facades
  (playback settings, appearance, sync, …), each with its own `DependencyKey` and isolation choice.
- **DataManager Sendable story**: the single decision that unblocks most of the remaining baseline
  (`RatePodcastViewModel`, `ShareProfileViewModel`, `PlaylistDetailViewModel`,
  `PlaylistMetadataLoader`/`ListEpisode`). Likely shape: keep GRDB record classes (`Episode`,
  `EpisodeFilter`, `Podcast`) non-Sendable and confine them, passing Sendable snapshots/DTOs across
  actor boundaries — decide once, document in MODERNIZATION.md, then burn down.
- **PlaybackManager facade** (protocol + key only; internals untouched) so consumers decouple ahead
  of Phase 5.
- **VC decomposition**: `PodcastViewController` (1,752 lines), `MainTabBarController` (998),
  `TranscriptViewController` (1,013) — extract data sources/routing/action handling as
  constructor-injected units. Lock in with a SwiftLint `type_body_length` shrinking exemption list.

### Phase 3 — Data layer (medium-high risk, ~20–40 small PRs)

Finish raw SQL → GRDB query interface in `PocketCastsDataModel` (one table/DAO per PR, parity
tests; this module has the best coverage in the repo), then **delete the `grdbQueryInterface` flag
and the legacy paths** — the biggest single flag-retirement win. Add a Semgrep rule forbidding new
raw-SQL execution outside a deletion-only residue list.

### Phase 4 — Complete strict concurrency (medium-high risk, ~30–60 PRs)

Flip to `SWIFT_STRICT_CONCURRENCY = complete`, regenerate the baseline (expect hundreds of entries —
fine, it's deletion-only from day one), and burn down leaf-first: utilities → injected services
(isolation already decided per key in Phase 2) → feature areas. Convert completion handlers to
async/await in non-playback subsystems as files are touched. **Swift 6 language mode is a separate
gate afterward**, per-target, extensions first.

### Phase 5 — Playback (deferred by decision)

`PlaybackManager` (2,355 lines), `DefaultPlayer`, `EffectsPlayer`, `VoiceBoostN`, the 18
playback-adjacent flags, and the remaining permanent baseline entries. Phases 1–4 create its
preconditions: a facade already isolates consumers, the rest of the app is isolation-clean, and the
ratchet localizes all remaining debt to this one subsystem. Plan it as its own effort with audio
expertise in the loop.

### Standing rules

- The baseline only shrinks. New `nonisolated(unsafe)` requires a justification comment (Semgrep
  enforces). `@unchecked Sendable` gating is planned once Phase 1 reduces the 123 legacy sites.
- Don't `@MainActor` a type whose tasks do synchronous DataManager/disk work without first moving
  that work to `Task.detached` or `nonisolated` helpers.
- When a fix reveals a generalizable problem class, encode it as a Semgrep rule (repo convention).
