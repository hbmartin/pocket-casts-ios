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
| Strict-concurrency warnings (app + modules + tests) | `check-concurrency-warnings.sh` + `scripts/ci/concurrency-baseline.txt`; app target builds with `SWIFT_STRICT_CONCURRENCY = targeted`, modules with the `StrictConcurrency` upcoming feature | Active (Phase 1 burn-down; baseline includes a handful of pre-existing module/test warnings that CI's incremental builds never surfaced) |
| `nonisolated(unsafe)` without justification | Semgrep `pocketcasts.nonisolated-unsafe-requires-justification` | Active (zero findings) |
| `@unchecked Sendable` without justification | Not yet gated — 123 legacy sites; gate after Phase 1 reduces them | Planned |

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

**Exit criteria:** baseline at zero for targeted mode (playback files excepted); top-level UI types in
non-playback features are `@MainActor`.

## Phase 2 — DI adoption & view-controller decomposition (medium risk)

**Sequencing rationale:** DI comes *before* complete-mode concurrency so the isolation decision for each
singleton is made once, at its `DependencyKey`, instead of re-touching ~711 `.shared` call sites twice
(once for injection, once for isolation).

- **2a — Singleton seams.** For each of `DataManager.sharedManager`, `DownloadManager.shared`,
  `ServerSettings`, `Settings` (split the 1,595-line god object into focused protocol facades), and
  `FileLog.shared`: define a protocol, add a `DependencyKey` (deciding its isolation: `@MainActor`,
  actor-backed, or lock-protected), register the existing singleton as the default value, then adopt
  `@Dependency` at call sites in feature-area batches. The existing adopters
  (`PlaylistsViewController`, `NewPlaylistCell`, `PlaylistDetailViewModel`) are the pattern template.
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

## Phase 3 — Data layer: raw SQL → GRDB query interface (medium-high risk)

- Finish the migration the `grdbQueryInterface` flag (default-on) already started: convert the ~168 raw
  `.execute()`/SQL sites in `Modules/Sources/PocketCastsDataModel` to GRDB query interface, using the
  `GRDBMacros` record conformances. One DAO/table area per PR, with before/after parity tests —
  DataModel has the strongest test suite in the repo; extend it per area.
- Then **delete the `grdbQueryInterface` flag and the legacy raw-SQL paths** — the largest single
  flag-retirement win.
- This work lives inside the SPM modules where strict concurrency is already enforced at zero warnings,
  so all new data-layer code is born clean; GRDB's async access patterns replace bespoke
  `DispatchQueue` plumbing, pre-shrinking Phase 4.
- **Lock-in:** Semgrep rule forbidding new raw-SQL string execution in DataModel outside a
  deletion-only residue list (migrations and justified perf-critical bulk ops may stay raw).

**Exit criteria:** `grdbQueryInterface` deleted (single code path); raw SQL only in the justified
residue list.

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

## Phase 5 — Deferred: playback/audio

`PlaybackManager` (2,355 lines), `DefaultPlayer` (950), `EffectsPlayer`, the `VoiceBoostN` C/ObjC code,
their feature flags, and their baseline entries. Phases 1–4 create the preconditions: a facade protocol
and `DependencyKey` already exist (Phase 2), the rest of the app is isolation-clean (Phase 4), and the
ratchet localizes remaining debt to this subsystem. Sizing and approach to be planned when this phase
opens.

## Sizing & dependency summary

| Phase | Risk | Rough size | Unblocks |
|---|---|---|---|
| 0 Foundations & cleanup | Low | ~6–10 small PRs | 1, 2 (tooling; fewer dual paths) |
| 1 Targeted concurrency | Low-Med | ~5–10 PRs | 2 (isolation decisions), 4 |
| 2 DI + VC decomposition | Med | ~20–35 PRs, parallelizable | 3 (repo protocols), 4 |
| 3 Data layer | Med-High | ~20–40 small mechanical PRs | 4 (shrinks burn-down) |
| 4 Complete concurrency | Med-High | ~30–60 PRs | 5 |
| 5 Playback (deferred) | High | TBD | — |
