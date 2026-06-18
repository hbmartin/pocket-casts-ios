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

## Decision: **Strategy B — full struct migration**

Chosen despite the higher cost: records become value-type structs (the GRDB-7 north star), which means
first rewriting the shared-cache / active-record / in-place-mutation model that the spike exposed. To
contain the regression risk on a UI-test-light subsystem, this proceeds **refactor-then-convert,
leaf-first, with GRDB round-trip + behaviour-parity tests landed *before* each record flips to a struct**
(extending the DataModel suite, which has the strongest coverage in the repo). Sequence below.

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

## Progress

- **Record 1 — `Folder`: DONE** (Sendable struct; first production `@GRDBRecord` struct, proving the
  macro's struct path end-to-end). Validated: DataModel 448 / Server 40 / app 259, 0 failures.

## Record 2 — `EpisodeFilter` (survey complete; not yet started)

Far heavier than `Folder` — sized as its own multi-session effort. Survey findings:

- **~80 property-mutation sites** + the mutating methods `setTitle` / `addPodcast` / `removePodcast`
  (become `mutating func`; their `let`/parameter call sites need `var`).
- **~40 `save(playlist:)` call sites.** `PlaylistDataManager.save` back-mutates `id`
  (`DBUtils.generateUniqueId()` when `id == 0`) and `playlistUpdateDate` — same return-the-saved-value
  refactor as `Folder.save`, but ×40 callers, across `DataManager` + the `PlaylistRepository` protocol +
  its mock.
- **~40 `NotificationCenter` posts** pass the filter as `object:` (e.g. `playlistChanged`). Boxing a
  value type works and `notification.object as? EpisodeFilter` still reads it, but every receiver that
  assumes a shared/reference object must be checked — a risk class `Folder` did not have.
- **`Set<EpisodeFilter>`** (`ManualPlaylistsChooserViewController`) + the current `isEqual`-by-`uuid` /
  `hash`-by-`id` (an inconsistent pairing). Replace with a uuid-consistent `Equatable`/`Hashable`.
- **`@objc`/KVC risk:** the filter-edit overlays are XIB-based; storyboard/KVC bindings to `@objc`
  properties fail at *runtime*, not compile time, so the existing unit suites may not catch them —
  needs manual verification of the filter-editing flows.
- **200+ test instances** across 15+ files need `let`→`var`.

Sequencing note: because `EpisodeFilter` alone is this large — and `Podcast` (143 refs) and
`Episode`/`UserEpisode` (~200+ each, gated on de-`@objc`-ing `BaseEpisode`) are larger still — revisit
whether Strategy B remains the right call for the *heavy* records, or whether the confine+snapshot
fallback (Strategy A) should cover them while only the leaves go struct. Decide with this evidence.

## Exit criteria

- ✅ Reference-semantics spike answered: **rewrite, not rename** (above).
- Strategy A/B/C chosen and recorded; MODERNIZATION.md Phase 3 reconciled with the choice.
- Under A/C: `EpisodeFilter`/`Folder` `Sendable` with confinement contract; the snapshot hops that clear
  the 10 baseline entries + 7 repository keys identified and ticketed.
- Under B: the cache/mutation refactor landed with parity tests before any record becomes a struct.
