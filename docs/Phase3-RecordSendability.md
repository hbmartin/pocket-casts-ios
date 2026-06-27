# Phase 3 Scoping — Record Sendability (GRDB-7 struct migration)

Scopes the record-layer Sendability work parked by [MODERNIZATION.md](../MODERNIZATION.md) Phase 3.
This is the linchpin: it unblocks **10 of the 13** remaining strict-concurrency baseline entries
(`PlaylistDetailViewModel`, `PlaylistMetadataLoader`, `ShareProfileViewModel`), the **7 repository
`DependencyKey`s** still on the homegrown DI container, and the dominant error class for Phase 4
complete-mode. It is also the deepest, highest-risk refactor in the roadmap — hence this written pass
before any code.

## North star (already decided)

The repo is on **GRDB 7.10.0**, whose concurrency guidance prescribes **value-type `struct` records of
`Sendable` properties** and explicitly discourages `@unchecked Sendable` on record *classes*. The
end-state is therefore struct records — not DTO snapshots layered over class records, and not a global
`@unchecked` ratification. `PlaylistEpisode` (`final class … Codable, @unchecked Sendable`, no NSObject,
no `@objc`) is the closest existing exemplar of the target shape.

## Inventory

| Record | Decl | Mutable props | `@unchecked Sendable`? | Coupling that resists struct conversion | ~refs |
|---|---|---|---|---|---|
| **Folder** | `class: NSObject, Identifiable` | 8 `@objc var` | ❌ no | NSObject identity only (no `isEqual`/`hash` override); `Identifiable` (fine for structs) | ~100–150 (many false-positive name matches) |
| **EpisodeFilter** | `class: NSObject` | 27 `@objc var` | ❌ no | `isEqual`/`hash` override; no protocol burden | ~99 |
| **Podcast** | `class: NSObject, Identifiable` | 53 `@objc var` | ✅ yes | `isEqual`/`hash`; nested mutable `PodcastSettings` | ~143 |
| **UserEpisode** | `class: NSObject, BaseEpisode` | 34 `@objc var` | ✅ yes | **`@objc BaseEpisode` protocol**; `isEqual`/`hash` | ~218 |
| **Episode** | `class: NSObject, BaseEpisode` | 43 `@objc var` | ✅ yes | **`@objc BaseEpisode` protocol**; `isEqual`/`hash`; heaviest in-place mutation | ~212 |

## The enabler

`@GRDBRecord` **already supports both class and struct** conformers — `GRDBRecordMacro` branches on
`isNSObjectSubclass()` and emits a `Codable`-synthesised path for non-NSObject types (the path
`PlaylistEpisode`-style records already use). So per-record conversion is `class X: NSObject,
@GRDBRecord` → `struct X: @GRDBRecord`, without macro work.

## The blockers (in priority order)

1. **Reference semantics / shared mutation — the go/no-go risk.** These are active-record classes:
   load → mutate fields in place → `save()`, with the *same instance* often held and observed by
   multiple owners (e.g. `PlaybackManager` mutates the "now playing" episode and other holders expect to
   see it). Structs are value types — a mutation on one copy is invisible to other holders. Whether the
   app *relies* on shared-reference mutation/observation (KVO, NSObject identity `===`, in-place updates
   propagating) determines whether struct migration is a mechanical rename or a semantics rewrite.
   **This requires a focused spike before committing to the heavy records (see below).**
2. **`@objc BaseEpisode` protocol** (Episode, UserEpisode). An `@objc` protocol requires class
   conformers, so these two cannot become structs until `BaseEpisode` is de-`@objc`'d / re-expressed as
   a Swift protocol (or split). This is a prerequisite PR of its own and gates ~430 of the ~530 heavy
   call sites.
3. **NSObject / `@objc` / `isEqual`/`hash` / KVC.** Structs replace identity-`isEqual`/`hash` with
   `Equatable`/`Hashable` synthesis; every `@objc`, KVC, and `=== ` identity call site must be found and
   converted. Scales with `@objc` count (8 → 53 per record).

## Proposed sequence (easiest → hardest)

Ordered to prove the pattern on low-risk leaves first and to surface the reference-semantics risk early
on a record that is *not* on the playback hot path.

1. **Spike (no merge): reference-semantics audit.** Pick `Folder` and grep every site that holds a
   loaded record and mutates/observes it after load. Classify: (a) local load→mutate→save (struct-safe),
   (b) shared-instance mutation/observation (struct-breaking). Output: a go/no-go + the conversion recipe.
2. **Folder → struct (pilot).** Smallest, no `isEqual`/`hash` override, no protocol burden, off the
   playback path. Proves the end-to-end recipe (macro path, `Identifiable`, call-site fixes, GRDB
   round-trip parity tests). Closes Folder's Sendable gap.
3. **EpisodeFilter → struct.** Second leaf; unblocks the `ShareProfileViewModel` / `PlaylistDetailVM` /
   `PlaylistMetadataLoader` baseline entries and the playlist repository key. ~99 refs, no protocol burden.
4. **Podcast → struct.** 53 props + nested `PodcastSettings` (already a `Sendable` struct) + `Identifiable`.
5. **`BaseEpisode` de-`@objc` (prerequisite PR).** Re-express as a Swift protocol; fix the `@objc`/dynamic
   call sites.
6. **UserEpisode → struct, then Episode → struct.** Heaviest; gated on (1) and (5). Episode last — it is
   the most-mutated and most playback-coupled, so it also coordinates with Phase 5.

After each record converts, retire its homegrown repository `DependencyKey` to swift-dependencies (its
`liveValue`/value is now `Sendable`), and delete `PocketCastsDependencyInjection` once the last one moves.

## Interim baseline unblocking (bounded)

Where a single baseline entry needs a record to cross an actor boundary *before* that record is
struct-migrated, fix the specific hop locally — project the few displayed fields into a small `Sendable`
struct at that call site (per the MODERNIZATION.md Phase 3 rule). This is a per-entry escape hatch, **not**
a strategy: no new `@unchecked Sendable` on records, no app-wide DTO layer.

## Spike result (Folder reference-semantics audit) — **NO-GO for a mechanical rename**

The gating spike ran against `Folder`, the *easiest* record. It found material category-B reliance even
there, so struct conversion is a semantics rewrite, not a rename:

- **Shared cached instances.** `FolderDataManager` holds `private var cachedFolders = [Folder]()` and
  `findFolder`/`allFolders` return references into it. Callers mutate those instances expecting app-wide
  visibility (e.g. `PodcastListViewController+CollectionView.swift:131` sets `folder.sortOrder` on cached
  instances before `saveSortOrders()`). Value types return fresh copies → silent behaviour change.
- **In-place mutation of an out-parameter.** `FolderDataManager.save(folder:)` assigns
  `folder.uuid = UUID()…` when empty, and callers (`FolderModel.createFolder()`,
  `FoldersCoordinator.makeFolder()`) read `folder.uuid` back after `save`. With a struct the caller never
  sees the generated uuid.

(Two of the spike's flagged sites are *not* actually breaking — `@Published [(Podcast, Folder)]` works
under struct reassignment, the idiomatic SwiftUI pattern — but the shared-cache + in-place-mutation core
is real and decisive.)

**Implication.** GRDB 7's "use structs" guidance assumes records aren't a shared-mutable-cache active-record
layer; this one is. Following it literally means rewriting the cache/mutation/observation model of a
test-light subsystem with no UI tests — for *every* record, since the leaf is already this entangled.
That is a much larger, higher-risk effort than the slice-9 roadmap note assumed (which was written from
GRDB's guidance, before this evidence).

## Decision: **Strategy B for the leaves; heavy episodes deferred to Phase 5**

Records become value-type structs (the GRDB-7 north star), which means first rewriting the
shared-cache / active-record / in-place-mutation model the Folder spike exposed. To contain regression
risk on a UI-test-light subsystem, this proceeds **refactor-then-convert, leaf-first, with GRDB
round-trip + behaviour-parity tests landed *before* each record flips to a struct** (extending the
DataModel suite, which has the strongest coverage in the repo).

**Scope refined by the heavy-record spike (2026-06-27, below):** Strategy B applies to the *leaf*
records — `Folder` (done), `EpisodeFilter`, `Podcast`. `Episode`/`UserEpisode` are **reclassified out
of Phase 3 and coupled to Phase 5**: their only shared-mutation reliance lives in the playback engine
(deferred) and behind the `@objc BaseEpisode` protocol (a hard structural blocker). See the verdict
section. Sequence below.

## Revised strategy options (considered)

- **A — Confine + read-only Sendable snapshots (pragmatic; recommended).** Keep the records as confined
  classes; make the two holdouts (`EpisodeFilter`, `Folder`) `@unchecked Sendable` to match the three
  that already are, *with* a written confinement contract (records are owned by the awaiting task /
  effectively immutable after load; mutation only on the DataManager write path). Introduce small
  read-only `Sendable` struct snapshots only at the specific cross-actor hops the baseline/Phase 4 need.
  Achieves Swift 6 boundary-correctness without the semantics rewrite. GRDB 7 runs fine this way (it
  *discourages* `@unchecked` on records stylistically, but supports it). **Trade-off:** revises the
  slice-9 "struct end-state, no DTO snapshots" note — that note was guidance-based; this is evidence-based.
- **B — Full struct migration (north-star; very large).** Rewrite the shared-cache/active-record model
  (return copies, return generated ids instead of mutating out-params, replace shared-instance mutation
  with explicit reload), then convert records to structs leaf-first. Highest fidelity to GRDB 7, but a
  multi-PR semantics rewrite of a UI-test-less subsystem — high regression risk.
- **C — Hybrid.** Snapshots/confinement now (unblock Swift 6), full struct migration deferred to its own
  later epic with a dedicated test-coverage investment first.

## Heavy-record go/no-go (reference-semantics spike, 2026-06-27)

The line-155 sequencing note asked whether Strategy B should extend to the heavy records or whether
they should fall back to confine+snapshot. A four-part read-only spike (playback layer, DataManager
caching/identity, app-wide episode mutation, Podcast) answered it. The decisive questions were
*(1) does a load even hand out a shared instance?* and *(2) does anything mutate a held instance and
expect other holders to see it?*

| Record | Load returns | Identity reliance (`===`, Set/dict keys, KVO) | Verdict |
|---|---|---|---|
| **EpisodeFilter** | fresh per call (no cache) | none; convert `isEqual`/`hash` to uuid-consistent synthesis | ✅ **GO** — leaf struct (Strategy B) |
| **Podcast** | ⚠️ **shared cached instance** (`PodcastDataManager.cachedPodcasts: [String: Podcast]`) | none; `PodcastSettings` already a `Sendable` struct | 🟡 **GO after cache refactor** — same shape as the Folder `cachedFolders` fix, medium effort |
| **Episode / UserEpisode** | fresh per call | none outside playback | ❌ **NO-GO in Phase 3 — reclassified to Phase 5** |

**Cross-cutting positive:** outside the playback engine there is **zero reference-identity reliance** —
no `===`, no `ObjectIdentifier`, no records as Set/dict keys by identity, no KVO/`@objc dynamic`
observation. `isEqual`/`hash` are already value-based (uuid). The scariest struct-migration failure
class is simply absent.

**Why Episode/UserEpisode are NO-GO for Phase 3** — the shared-mutation reliance that *does* exist is
localized to exactly the two areas the roadmap already isolates:

1. **Playback engine (Phase 5).** `PlaybackQueue` caches `topEpisode` and
   `PlaybackManager.progressTimerFired` mutates `episode.playedUpTo` in place **~once per second**,
   relying on that held instance persisting (`PlaybackManager.swift:1503`, `PlaybackQueue.swift:314`,
   plus the `EpisodeDataManager.saveEpisode` side-effect mutation of the passed-in episode). Value
   semantics silently breaks this — a playback-position-tracking *redesign*, not a rename.
2. **`@objc BaseEpisode` protocol** (~116 existential sites, mostly function params). An `@objc`
   protocol requires class conformers, so `Episode`/`UserEpisode` cannot become structs until
   `BaseEpisode` is de-`@objc`'d — a standalone prerequisite PR.

The non-playback app layer is otherwise ~95% local `load→mutate→save` (struct-safe); the one app-layer
exception (`PlayerChapterCell` mutating the shared current episode) is itself playback-adjacent.

**The insight that unblocks the sequence:** the 10 baseline entries Phase 3 must clear
(`ShareProfileViewModel`, `PlaylistDetailViewModel`, `PlaylistMetadataLoader`) hang off **`EpisodeFilter`
and `ListEpisode`, not `Episode`**. So the full Phase 1 baseline payoff comes from the *leaf* records,
and the hard playback-coupled episode conversion defers to Phase 5 without blocking anything. Interim
boundary crossings that touch `Episode` use the per-hop `Sendable`-projection escape hatch.

## Progress

- **Record 1 — `Folder`: DONE** (Sendable struct; first production `@GRDBRecord` struct, proving the
  macro's struct path end-to-end). Validated: DataModel 448 / Server 40 / app 259, 0 failures.
- **Record 2 — `EpisodeFilter`: IN PROGRESS** (2026-06-27). Leaf record, no cache, no `@objc` protocol
  burden — confirmed GO by the spike.
- **Record 3 — `Podcast`: GO after cache refactor** (the `cachedPodcasts` identity-map must hand out
  fresh copies; sort-order flows reuse the Folder "collect mutated copies" fix).
- **Records 4/5 — `Episode`/`UserEpisode`: deferred to Phase 5** (gated on de-`@objc` `BaseEpisode` +
  playback position-tracking redesign).

## Record 2 — `EpisodeFilter` (in progress)

Far heavier than `Folder` — sized as its own multi-session effort. Survey findings:

- **~80 property-mutation sites** + the mutating methods `setTitle` / `addPodcast` / `removePodcast`
  (become `mutating func`; their `let`/parameter call sites need `var`).
- **`save(playlist:)` call sites — verified 28 in the app + the rest in tests.** `PlaylistDataManager.save`
  back-mutates `id` (`DBUtils.generateUniqueId()` when `id == 0`) and `playlistUpdateDate` — but a grep
  for read-back (`= …save(playlist`) found **zero** sites that consume the result. So the out-param
  back-mutation reliance that `Folder` had is **absent here**: the return-the-saved-value refactor across
  `DataManager` + `PlaylistRepository` + its mock can be additive (`@discardableResult`) with no caller
  edits.
- **`NotificationCenter` object-passing — not found.** A grep for `post(name:…)` passing a filter/playlist
  as `object:` returned nothing, contrary to the survey's ~40 estimate. Lower risk than feared; still
  spot-check receivers during the flip.
- **`Set<EpisodeFilter>`** at `ManualPlaylistsChooserViewController:180`. The old `isEqual`-by-`uuid` /
  `hash`-by-`id` pairing was inconsistent (Hashable-contract violation). **✅ Fixed 2026-06-27**: `hash`
  now keys on `uuid`, consistent with `isEqual` — a correctness fix independent of the flip, and the
  semantics the struct's `Equatable`/`Hashable` will carry.
- **`@objc`/KVC/XIB risk — did NOT materialize.** No `.xib`/`.storyboard` references `EpisodeFilter`/
  `SJFilteredPlaylist`, and no KVC (`value(forKey:)`/`setValue(forKey:)`) targets a filter property. The
  overlays hold a plain Swift `filter` property. `@objc` removal is still *mandatory* for the struct
  (Swift structs can't expose `@objc` members), so re-verify the create/edit/delete filter flows once
  flipped — but there is no hidden KVC binding to break.
- **200+ test instances** across 15+ files need `let`→`var`.

### Landed vs staged (2026-06-27)

- ✅ **`isEqual`/`hash` uuid-consistency** — landed (`EpisodeFilter.swift`, PR #111). Self-contained
  correctness fix; directly repairs the `ManualPlaylistsChooserViewController` `Set` dedup.

The struct flip itself is staged on branch `modernization-slice14-episodefilter-struct` (mechanical but
broad, and `@objc` removal is only runtime-verifiable), in this order:
  1. ✅ **`save(playlist:)` returns the saved value** — landed. `@discardableResult` returning the saved
     `EpisodeFilter`, threaded through `PlaylistDataManager` + `DataManager` + `PlaylistRepository` +
     mock. Written forward-compatibly (local `var` copy); additive — no caller reads it back today.
  2. ✅ **Behaviour-parity tests** — landed ahead of the flip (`EpisodeFilterBehaviorTests.swift`):
     uuid equality/hash + `Set` dedup, `addPodcast`/`removePodcast`/`setTitle`, removal-rule helpers,
     and `save`-returns-value round-trip parity across both DB code paths. Assertions read the *returned*
     value and use `==`/`hashValue`/`Set`, so they validate the struct conformances unchanged.
  3. ⏭ `class: NSObject` → `struct`, drop `@objc`, add `Sendable` + custom uuid `Equatable`/`Hashable`;
     `setTitle`/`addPodcast`/`removePodcast` → `mutating func`.
  4. ⏭ Compiler-driven `let`→`var` sweep at the ~28 app callers + 200+ test instances.
  5. ⏭ **Verification gate:** full `mise run test:staging` + manual QA of create/edit/delete filter flows
     (the only check that exercises the dropped `@objc` surface).

Sequencing note — **resolved** by the heavy-record spike above: Strategy B covers the leaves
(`EpisodeFilter`, then `Podcast`); `Episode`/`UserEpisode` are reclassified to Phase 5. EpisodeFilter
itself is unaffected by that split and proceeds now.

## Exit criteria

- ✅ Reference-semantics spike answered: **rewrite, not rename** (above).
- ✅ Strategy chosen and recorded: **B for the leaves** (`Folder`✓ → `EpisodeFilter` → `Podcast`),
  **`Episode`/`UserEpisode` deferred to Phase 5** (heavy-record spike, 2026-06-27).
- Leaf records (`Folder`✓, `EpisodeFilter`, `Podcast`) are `Sendable` structs with GRDB round-trip +
  behaviour-parity tests landed *before* each flip; `save(...)` returns the saved value (no out-param
  back-mutation); shared caches hand out copies.
- The 10 baseline entries + the playlist repository key clear once `EpisodeFilter` (+ honest-`Sendable`
  `ListEpisode`) land; Episode-touching boundary crossings use the per-hop `Sendable`-projection hatch
  until Phase 5.
- MODERNIZATION.md Phase 3 reconciled: heavy-record migration moves under the Phase 5 umbrella.
