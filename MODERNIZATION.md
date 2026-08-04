# Modernization Roadmap

The SPM modules under `Modules/` already enforce strict concurrency at zero warnings, ship async-first
APIs, and include a dependency-injection container. The main app (`podcasts/`, ~121K lines) lags behind:
Swift 5 language mode without strict concurrency, ~500 completion-handler signatures, 1,000+ GCD calls,
a singleton web (`DataManager.sharedManager`, `PlaybackManager.shared`, `Settings`, `ServerSettings`,
`FileLog.shared`) with the `PocketCastsDependencyInjection` module almost unused, ~168 raw-SQL sites in
DataModel behind the default-on `grdbQueryInterface` flag, and 67 accumulated feature flags.

This document sequences the catch-up. Each phase lists contents, risk, and exit criteria. Every PR in
every phase is verified with the existing rails: `mise run test:staging`, `mise run check:static`,
`mise run check:concurrency`.

**Out of scope until Phase 5:** playback/audio engine internals (`PlaybackManager`, `DefaultPlayer`,
`EffectsPlayer`, `VoiceBoostN`, and their feature flags). **Out of scope entirely (for now):**
UIKit → SwiftUI screen migration.

## Ratchet principle

All enforcement added by this effort is a **deletion-only allowlist** (a "ratchet"): a baseline file
captures the current debt, CI fails on anything not in the baseline, and baseline entries may only ever
be removed, never added. Count-based ratchets are deliberately avoided — CI uses incremental builds that
under-report warnings, so counts are unreliable, but per-entry presence semantics survive incremental
builds (introducing a warning requires changing a file, and changed files are recompiled; see the header
of `scripts/ci/check-concurrency-warnings.sh`).

### Current ratchet status

| Ratchet | Mechanism | Status |
|---|---|---|
| Strict-concurrency warnings (app + modules + tests) | `check-concurrency-warnings.sh` + `scripts/ci/concurrency-baseline.txt`; app target builds with `SWIFT_STRICT_CONCURRENCY = targeted`, modules with the `StrictConcurrency` upcoming feature | Active (baseline at **3** as of 2026-07-01 — the permanent `DefaultPlayer`/`PlaybackManager` playback floor; the non-playback targeted-mode burn-down is complete) |
| `nonisolated(unsafe)` without justification | Semgrep `pocketcasts.nonisolated-unsafe-requires-justification` | Active (zero findings) |
| `@unchecked Sendable` without justification | Not yet gated — 123 legacy sites; gate after Phase 1 reduces them | Planned |

> **Coverage note:** `mise run check:concurrency` builds the app target only; CI runs the same
> ratchet on the test log (app + test + module targets). So test- and module-target baseline
> entries are gated in CI but appear locally only as `Info:` (run with `--show-resolved` to list
> them) — that is expected, not a stale baseline.

## Phase 0 — Foundations & cleanup (low risk)

- **Ratchet tooling** (done in the first slice): app-target `targeted` strict concurrency, two-tier
  warning gate, baseline file, `mise run concurrency:baseline` regeneration task, Semgrep escape-hatch
  rule.
- **Feature-flag audit.** Retirement is *not* unilaterally decidable from code: nearly every flag in
  `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift` has a live remote kill-switch key
  (the `remoteKey` fallthrough derives one from the case name). The audit table lives in
  [docs/FeatureFlagAudit.md](docs/FeatureFlagAudit.md) — 71 flags: 4 dead (zero call sites), ~36
  retirement candidates, 18 playback-adjacent (deferred to Phase 5 regardless). Each retirement needs
  remote-config sign-off recorded in that table, then removal PRs in batches of 3–5 related flags.
- **Objective-C ports — bounded.** `SJCommonUtils.catchException` cannot be ported (NSException trapping
  has no Swift equivalent; 7 Swift call sites), so the bridging header keeps at least that import.
  `SJMediaMetadataHelper` is portable only by going async (its `AVAsset.commonMetadata` use is
  deprecated), which ripples into the synchronous `ImageManager.loadEmbeddedImageIfRequired` flow — do
  it when that flow is touched for async migration in Phase 4. `NSNull+Length` is a dynamic-dispatch
  crash guard with zero static call sites; deletion requires crash-log archaeology, not grep.

**Exit criteria:** ratchet tooling live in CI; flag audit table reviewed; first flag-removal batch landed.

## Phase 1 — Targeted strict concurrency in the app target (low-medium risk)

- `SWIFT_STRICT_CONCURRENCY = targeted` is set in `config/PocketCasts.base.xcconfig` (a dedicated build
  setting — not `OTHER_SWIFT_FLAGS`, which staging/prototype configs redefine). `targeted` only checks
  code that already adopts concurrency (async functions, `Task {}`, `@MainActor` types), so the warning
  set is the app's existing async code — exactly what needs checking first.
- Burn down `scripts/ci/concurrency-baseline.txt` in small PRs. Typical fixes: `static var` → `static
  let`, `@MainActor` on UI-touching completion hops, making small value types `Sendable`. No
  `nonisolated(unsafe)` / `@unchecked Sendable` without a justification comment (Semgrep warns).
- Systematically `@MainActor`-annotate view controllers, views, and coordinators in non-playback
  feature areas. This is cheap under `targeted` mode and is the main input to Phase 2's per-singleton
  isolation decisions.
- **Main-actor hop convention.** To call main-actor-isolated code from a non-isolated or background
  completion handler, use `Task { @MainActor in … }`. Reserve `DispatchQueue.main.async` for
  not-yet-migrated code or where strict FIFO ordering relative to other `DispatchQueue.main.async` work
  is required. Don't mix the two within a single function/flow. Note: under `targeted` mode (Swift 5
  language mode) a `@MainActor`-isolated *function type* is **not** implicitly `Sendable` (SE-0434 only
  applies in the Swift 6 language mode), so typing a delivered closure `@escaping @MainActor (…) -> Void`
  does **not** let it cross into a `@Sendable` completion handler — a non-`Sendable` closure that must
  cross such a boundary still needs an `UncheckedSendable` box with a justification comment. When the
  hand-off *value* is non-`Sendable` (e.g. `BaseEpisode`), produce it *inside* the `@MainActor` closure
  rather than capturing it across the boundary.

**Exit criteria:** baseline at zero for targeted mode (playback files excepted); top-level UI types in
non-playback features are `@MainActor`.

**Status (2026-07): met.** The targeted-mode baseline is at its playback-only floor of **3** entries
(`DefaultPlayer` ×2, `PlaybackManager` ×1 — deferred to Phase 5); every non-playback entry has been
burned down. The final 10 (`PlaylistDetailViewModel`, `PlaylistMetadataLoader`/`ListEpisode`,
`ShareProfileViewModel`) were design-gated on the Phase 3 leaf-record Sendability work and cleared once
those landed — `ListEpisode` marked honestly `Sendable`, `ImageManager.podcastUrl` made a `static` pure
function, and the two view models annotated `@MainActor` with their synchronous DataManager work moved
off the main actor (slice 17, ratchet 13 → 3). View-controller/view `@MainActor` annotation continues
opportunistically as an input to Phase 2.

## Phase 2 — DI adoption & view-controller decomposition (medium risk)

**Sequencing rationale:** DI comes *before* complete-mode concurrency so the isolation decision for each
singleton is made once, at its `DependencyKey`, instead of re-touching ~711 `.shared` call sites twice
(once for injection, once for isolation).

- **DI library: pointfree [swift-dependencies](https://github.com/pointfreeco/swift-dependencies).**
  The repo's original homegrown `PocketCastsDependencyInjection` container keyed dependencies on a
  mutable `static var currentValue` (global mutable state — itself a concurrency smell requiring
  `nonisolated(unsafe)`). It is being replaced by swift-dependencies, whose `DependencyKey`
  (`liveValue`/`testValue`/`previewValue`), task-local `DependencyValues`, and scoped `withDependencies`
  overrides are concurrency-aware and remove the global mutable state. The `@Dependency(\.key)`
  call-site syntax is identical, so adopters only swap an import. **Migration complete (2026-07-02,
  slice 18):** `\.fileLog`, `\.downloadManager`, `\.playlistMetadataLoader` (+ its cache-invalidation
  coordinator), and the seven repository keys in `Repositories+Dependency.swift`. The repository
  protocols are now `Sendable` (with `DataManager` `@unchecked Sendable` — immutable stored
  references; thread safety delegated to GRDB's pool and the sub-managers' private queues), so the
  keys satisfy swift-dependencies' `Sendable` `DependencyValues`. The homegrown
  `PocketCastsDependencyInjection` module is **deleted**.
  **Next steps for this thread, in order:** (1) call-site adoption batches — `FileLog.shared` (~640
  sites) and `DownloadManager.shared` (~110 sites) to `@Dependency`, one feature area per PR, plus
  repository-key adoption in new `DataManager` consumers (`ArchiveHelper`/`PlaybackTimeHelper` are the
  template: method-local `@Dependency` reads, or an optional init parameter resolved from an init-local
  `@Dependency` — default arguments cannot read `DependencyValues`); (2) the remaining seams —
  `Settings`/`ServerSettings` protocol facades and the `PlaybackManager` consumer facade (2a below);
  (3) once a singleton's call sites are fully migrated, add the Semgrep `.shared`-access lock-in rule
  for it (see Lock-in below).
  _(Update 2026-07-09: the `PlaybackManager` consumer facade and a `Theme` seam are in —
  `PlaybackManaging` + `\.playbackManager` and `Theming` + `\.theme` in
  `podcasts/Utilities/{PlaybackManager,Theme}+Dependency.swift`, following the `DownloadManaging`
  consumed-surface pattern. The generated color accessors (`Theme+Color.swift`) moved to
  `extension Theming`, and `AppTheme.color(for:theme:)` takes `any Theming`, so `@Dependency(\.theme)`
  consumers keep the `theme.primaryUi02` spelling; `.environmentObject(Theme.sharedTheme)` sites stay
  concrete by design. Both keys mirror `testValue` to `liveValue` for the same reason the repository
  keys do. Mocks (`PlaybackManagingMock`, `ThemingMock`) plus override tests landed with the seams.
  Pilot conversion covered 14 small feature dirs (~43 sites): Analytics, Bookmarks, Fingerprint,
  Folder History, Lists, Notifications, Onboarding, Profile-SwiftUI, Ratings, Share Profile, Sharing,
  Syncing, Up Next History, Playlists Onboarding. Remaining backlog by grep: `DataManager.sharedManager`
  ~446 sites / 129 files, `PlaybackManager.shared` ~386 / 69 (engine/player-callback files stay on the
  singleton by design), `Theme.sharedTheme` ~273 / 68 (many are `environmentObject`/concrete-`Theme`
  sites that should not convert). Known seam gaps found during conversion: `activateAudioSession` is
  not on `PlaybackManaging` (blocks `ClipPlaybackManager`). (The former `DataManager+FileSync`
  seam gap resolved itself when the file-sync engine was removed.))_
- **2a — Singleton seams.** For each of `DataManager.sharedManager`, `DownloadManager.shared`,
  `ServerSettings`, `Settings` (split the 1,595-line god object into focused protocol facades), and
  `FileLog.shared`: define a protocol, add a swift-dependencies `DependencyKey` (deciding its isolation
  via the value type: `@MainActor`, actor-backed, or lock-protected), expose it on `DependencyValues`
  with the production singleton as `liveValue`, then adopt `@Dependency` at call sites in feature-area
  batches. The existing adopters
  (`PlaylistsViewController`, `NewPlaylistCell`, `PlaylistDetailViewModel`) are the pattern template.
  Note: for `DataManager` the seam is about *injectability and consumer isolation*, not about making
  the records it returns `Sendable` — that record-layer decision is GRDB-7-driven and lives in Phase 3,
  so don't try to resolve it at the `DependencyKey`.
  `PlaybackManager` gets a facade protocol + key so *consumers* decouple, but its internals stay
  untouched. Each seam PR adds at least one test overriding the new `DependencyKey` — DI makes
  previously untestable units testable.
- **2b — VC splits** (after seams exist, so extracted units are born constructor-injected):
  `PodcastViewController` (1,752 lines — data source, header, action handling),
  `MainTabBarController` (998 — deep-link routing, tab construction), `TranscriptViewController`
  (1,013 — display only; skip player-internal reaches), `EpisodeDetailViewController` (781). Keep
  split PRs move-only where possible; there are no UI tests, so reviewability is the safety net.
- **Lock-in:** Semgrep rule flagging `.shared`/`.sharedManager` access to *migrated* singletons outside
  a deletion-only allowlist; add SwiftLint `type_body_length` with a generous threshold and a shrinking
  exemption list.

**Exit criteria:** the five core singletons injectable behind protocols; no non-playback, non-generated
file over 1,000 lines; regression rules active.

## Phase 3 — Data layer: raw SQL → GRDB query interface + record Sendability (medium-high risk)

- Finish the migration the `grdbQueryInterface` flag (default-on) already started: convert the ~168 raw
  `.execute()`/SQL sites in `Modules/Sources/PocketCastsDataModel` to GRDB query interface, using the
  `GRDBMacros` record conformances. One DAO/table area per PR, with before/after parity tests —
  DataModel has the strongest test suite in the repo; extend it per area.
- Then **delete the `grdbQueryInterface` flag and the legacy raw-SQL paths** — the largest single
  flag-retirement win.
- This work lives inside the SPM modules where strict concurrency is already enforced at zero warnings,
  so all new data-layer code is born clean; GRDB's async access patterns replace bespoke
  `DispatchQueue` plumbing, pre-shrinking Phase 4.
- **Record Sendability is decided here, and GRDB 7 has already prescribed the answer.** The repo is
  already on GRDB **7.10.0** (`Modules/Package.swift`: `from: "7.0.0"`), whose Swift-concurrency
  guidance is explicit: `db.read`/`db.write` take `@Sendable` closures whose return values must be
  `Sendable`; **record types should be value-type structs of `Sendable` properties**; the `Record`
  class "is not `Sendable`, and its use is actively discouraged since GRDB 7"; and `@unchecked
  Sendable` on a record class is called out as a footgun ("all humans and machines who read your code
  will think the class is thread-safe"). The repo's `@GRDBRecord`-macro'd `NSObject` records
  (`Episode`, `Podcast`, `EpisodeFilter`, `UserEpisode`, …) are exactly that anti-pattern — several
  already carry `@unchecked Sendable`. The endorsed end-state is **struct records**, not DTO snapshots
  layered over class records. This is the deepest refactor in the roadmap (hundreds of in-place
  active-record mutation sites, `@objc` bridging, a class-keyed macro, `BaseEpisode`/`ListItem`
  wrappers), so it is sized as its own sub-effort *inside* Phase 3, sequenced after the query-interface
  conversions inform feasibility. It is **not** pulled forward into Phase 1/2 burn-down: GRDB 7 runs
  fine under `targeted` Swift 5 mode today, so nothing forces the decision early. Where a Phase 1/2
  baseline entry needs a record to cross an actor boundary before then, fix it *locally and
  non-committally* (project the few displayed fields to a small `Sendable` struct at that hop; mark
  genuinely-immutable wrappers like `ListEpisode` honestly `Sendable`) rather than ratifying a global
  `@unchecked Sendable` contract that GRDB 7 would have us unwind.
- **Lock-in:** Semgrep rule forbidding new raw-SQL string execution in DataModel outside a
  deletion-only residue list (migrations and justified perf-critical bulk ops may stay raw). Once the
  struct-record migration begins, a companion rule flagging new `@unchecked Sendable` on `@GRDBRecord`
  types outside a shrinking allowlist.

**Status (2026-06):** Record-Sendability strategy resolved and the leaf-record migration **complete** —
see [docs/Phase3-RecordSendability.md](docs/Phase3-RecordSendability.md). A reference-semantics spike
established **Strategy B (struct records) for the leaves** — `Folder` ✓, `EpisodeFilter` ✓, `Podcast` ✓
(2026-06-28) are now `Sendable` value-type structs — while **`Episode`/`UserEpisode` are reclassified
out of Phase 3 and coupled to Phase 5**: their only shared-mutation reliance lives in the playback
engine (deferred) and behind the `@objc BaseEpisode` protocol (a hard structural blocker needing a
standalone de-`@objc` PR).

**Update (2026-07):** the baseline payoff from the leaf records has now been realized — slice 17 cleared
the 10 non-playback baseline entries that hung off `EpisodeFilter`/`ListEpisode` (`ListEpisode` marked
honestly `Sendable`; the `PlaylistDetailViewModel`/`PlaylistMetadataLoader`/`ShareProfileViewModel`
consumers moved to `@MainActor`/off-main), taking the ratchet from 13 → 3. The seven repository
`DependencyKey`s moved to swift-dependencies and the homegrown DI container was deleted on 2026-07-02
(slice 18). The **raw-SQL → query-interface conversion + `grdbQueryInterface` deletion remains the
outstanding Phase 3 thread**.

**Exit criteria:** `grdbQueryInterface` deleted (single code path); raw SQL only in the justified
residue list; record-Sendability strategy (struct migration) documented and underway, with the
`@unchecked Sendable` record population shrinking rather than growing. _(Leaf records done; heavy
episodes moved under the Phase 5 umbrella.)_

## Phase 4 — Complete strict concurrency + async migration (medium-high risk)

- Flip to `SWIFT_STRICT_CONCURRENCY = complete` and regenerate the baseline from a clean build (expect
  hundreds of entries initially — fine; it is deletion-only from day one). Burn down leaf utilities →
  injected-service conformances (isolation already decided per-`DependencyKey` in Phase 2) → feature
  areas. **Playback files stay in the baseline until Phase 5.**
- Convert completion-handler APIs (~507 signatures) to async/await in non-playback subsystems — the
  server layer is already async-first (`ApiServerHandler`); propagate inward. Replace
  `DispatchQueue.async` hops with structured concurrency where touched. Modernize NotificationCenter
  observation opportunistically (typed/async-sequence wrappers), not as a sweep.
- **Swift 6 language mode is a separate, explicit gate** after the baseline is near zero: per-target,
  extensions first (Widget/Intents/Notification — smallest), main app last; full 6.0 on the app target
  is contingent on Phase 5.
- **Lock-in:** the same ratchet script in complete mode; encode recurring fix patterns discovered during
  burn-down as Semgrep rules (the existing `no-notificationdelegate-mainactor-assumeisolated` and
  `timer-assumeisolated-requires-main-runloop` rules are this genre).

**Exit criteria:** complete-mode baseline contains only playback files; non-playback completion-handler
APIs converted or explicitly kept with rationale.

## Phase 5 — COMPLETE: playback/audio

**Completed 2026-07-05** (PRs #233–#242; design and per-slice record in
`docs/Phase5-PlaybackModernization.md`). What landed:

- `PlaybackManager`, `PlaybackQueue`, and the playback helpers are honestly `@MainActor`; the
  Up Next queue is fully encapsulated behind PlaybackManager; `PlaybackServerAdapter` bridges the
  server delegate synchronously onto the main actor.
- The real-time engine boundary (`DefaultPlayer` render taps, `AudioReadTask`/`AudioPlayTask`
  queues, VoiceBoostN C DSP) is preserved, narrowed, and documented: engines hop per-event into the
  main actor and read state through lock-guarded nonisolated mirrors — never synchronously into
  isolated code.
- `PlaybackPositionTracker` owns the transient playing position; the per-second in-place
  `episode.playedUpTo` mutation is gone.
- `BaseEpisode`, `FilePathProtocol`, and `PlaybackProtocol` are plain Swift protocols, and
  **`Episode` and `UserEpisode` are Sendable value types** — completing the record-Sendability arc
  (Folder, EpisodeFilter, Podcast, UpNextChanges, UserEpisode, Episode).
- The `voiceBoostN` flag remains (TestFlight-only; retirement needs remote-config sign-off).

With this, every phase of the roadmap (0–5) is complete: strict concurrency `complete` everywhere,
all first-party targets and packages on Swift 6 language mode, an empty warning baseline enforced by
the deletion-only ratchet, GRDB-unconditional data layer, and value-semantic Sendable model records.

## Swift 6.2 default isolation (adopted 2026-07-05)

The app target now builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
`SWIFT_APPROACHABLE_CONCURRENCY = YES` (all four configurations; extension targets excluded — they
run off-main). Unannotated app-target declarations are `@MainActor` by default; the utility, model,
playback-engine, and I/O layers (~80 files) carry explicit `nonisolated`. Generated code cooperates
via a custom SwiftGen stencil (`swiftgen-templates/strings-nonisolated.stencil`), checked-in intent
classes (`podcasts/Intents Generated/`, codegen disabled), and `scripts/themes/generate_themes.rb`.

The sharpest adoption gotcha: default isolation makes even *synthesized* deinits `isolated` (they
hop through `swift_task_deinitOnExecutor`), which crashes synchronous XCTest methods that deallocate
a MainActor object (swiftlang/swift#87316) — classes exercised by unit tests carry an explicit
`nonisolated deinit {}` as the workaround. Other rules that recur: class-level `nonisolated` does
not cover extensions (each extension needs its own), `nonisolated` cannot apply to `lazy var`, and
an unannotated protocol becomes `@MainActor` and drags witnesses in `nonisolated` classes onto the
main actor (fix at the protocol).

## Sizing & dependency summary

| Phase | Risk | Rough size | Unblocks |
|---|---|---|---|
| 0 Foundations & cleanup | Low | ~6–10 small PRs | 1, 2 (tooling; fewer dual paths) |
| 1 Targeted concurrency | Low-Med | ~5–10 PRs | 2 (isolation decisions), 4 |
| 2 DI + VC decomposition | Med | ~20–35 PRs, parallelizable | 3 (repo protocols), 4 |
| 3 Data layer | Med-High | ~20–40 small mechanical PRs | 4 (shrinks burn-down) |
| 4 Complete concurrency | Med-High | ~30–60 PRs | 5 |
| 5 Playback (deferred) | High | TBD | — |
