# Phase 5 — Playback/Audio Modernization Plan

_Opened 2026-07-05, after Phase 4 completed (Swift 6 language mode everywhere, concurrency baseline
empty) and Phase 3 exited (GRDB query interface unconditional, raw-SQL legacy deleted). This document
is the sizing-and-approach plan that MODERNIZATION.md deferred "until this phase opens." It records
the subsystem inventory, the isolation design, and the slice sequence._

## Where Phase 4 left the subsystem

Everything compiles under Swift 6 today, but the playback floor was bridged, not redesigned: audited
`@unchecked Sendable` annotations with internal-synchronization rationales, `UncheckedSendable` boxes
at closure/Task crossings, and `Thread.isMainThread ? MainActor.assumeIsolated : DispatchQueue.main.sync`
bridges for UIKit touches. Phase 5 replaces those bridges with honest isolation where possible, and
keeps (and documents) the ones that are architecturally required by real-time audio.

## Inventory (what exists, how it synchronizes)

| Component | Lines | Isolation today | Notes |
|---|---|---|---|
| `PlaybackManager` | ~2,400 | `@unchecked Sendable`; a few `AtomicBool`s + `playerCleanupQueue`; most state de-facto serial, unguarded | God-object singleton; 485 call sites across 87 files; API called from UI, remote commands, intents, AV callbacks *by design* |
| `DefaultPlayer` | ~980 | `@unchecked Sendable`; KVO/main flow + atomic C-pointer state | AVPlayer engine; **real-time** `MTAudioProcessingTap` + `AURenderCallback` code |
| `EffectsPlayer` | ~490 | `@unchecked Sendable`; `playerLock` + serial seek queue + `AtomicBool`s | AVAudioEngine engine for downloads (trim silence, boost) |
| `AudioReadTask` | ~410 | dedicated queue + `objc_sync` lock + semaphores | Producer: file → PCM buffers (+VoiceBoostN DSP) |
| `AudioPlayTask` | ~110 | dedicated queue + `updateQueue` for counters | Consumer: schedules buffers; calls back into `PlaybackManager` from its queue |
| `PlaybackQueue` | ~490 | plain class, convention-confined via PlaybackManager | Up Next CRUD; caches `topEpisode`; leaked directly to UI via `.queue` (43 sites) |
| `ChapterManager` | ~265 | plain class; detached parse tasks with boxed self | Owned by PlaybackManager; hot `checkForChapterChange` ~1/sec |
| `SleepTimerManager` / `FadeOutManager` / `BackgroundShakeObserver` / `Debounce` | ~250 total | mix of `@unchecked Sendable` + convention | Timer/main-driven helpers owned by the playback flow |
| `VoiceBoostN.c/.h` | ~800 | pure C, opaque `VBNState*` | LUFS loudness DSP, called from render threads |

Existing seams: `PlaybackProtocol` (`@objc`, the engine abstraction `PlaybackManager.player`),
`PlaybackFacade` (Sendable protocol for App Intents, `LivePlaybackFacade` → shared),
`ServerPlaybackDelegate` (server module), `TranscriptPlaybackManaging`. No playback `DependencyKey` yet.

## Design decisions

### D1. The real-time boundary is load-bearing — actors stop above it

`DefaultPlayer`'s tap/render callbacks and `AudioReadTask`/`AudioPlayTask`'s queue loops run on Core
Audio's real-time threads (or feed them). They can never be actor-isolated or async: no allocation,
no locks that priority-invert, no executor hops. **These stay synchronous queue/semaphore code with
`@unchecked Sendable` + rationale, permanently.** The modernization goal for the engine layer is to
*narrow and document* the boundary, not to eliminate it:

- Real-time code must not call into isolated code synchronously. Today `AudioPlayTask` calls
  `PlaybackManager.shared.playerDidFinishPlayingEpisode()` / `playbackDidFail()` directly from its
  audio queue, and `DefaultPlayer`'s KVO/notification callbacks call the whole `playerDid*` surface
  from arbitrary threads. These become **hops** (`Task { @MainActor … }`) — they are per-event
  (finish, fail, duration known), never per-buffer, so a hop is free.

### D2. `PlaybackManager` becomes honestly `@MainActor`

The de-facto execution model is already main-centric: the progress timer runs on the main run loop,
remote-command handlers arrive on main, the overwhelming majority of the 485 call sites are UI code,
and every UIKit/NowPlaying touch is already bridged *to* main. The class's "called from anywhere"
contract is real but thin — the off-main inbound edges are enumerable:

1. Player delegate callbacks (`playerDid*`, `playbackDidFail`, `requiredStartingPosition`) — hop.
2. `AudioPlayTask` completion/failure — hop.
3. NotificationCenter selectors (route change, interruption) — deliver on main queue or hop.
4. App Intents / Siri (`PlaybackFacade`) — already async; `await MainActor.run` at the facade.
5. Background code paths (EpisodeManager, DownloadManager, sync) that query `playing()` /
   `currentEpisode` — the long tail; each becomes an async hop or gets a snapshot API.

`requiredStartingPosition` is the one *synchronous request-response* call from an engine thread; it
gets a precomputed snapshot (set at `load` time) instead of a live query.

Payoff: ~30 unguarded mutable properties become actor-protected by construction; the
`assumeIsolated`/`main.sync` bridges and most boxes are deleted; `@unchecked Sendable` comes off.
Sub-owned helpers (`ChapterManager`, `SleepTimerManager`, `FadeOutManager`, `Debounce`,
`BackgroundShakeObserver`) are `@MainActor` with it — they are driven by the main-run-loop timer
already. `PlaybackQueue` also becomes `@MainActor` (its sync timer is already main-bridged), with its
DB work explicitly dispatched off-main where it is today.

Risks and their controls:
- **Sync query from off-main** (e.g. `currentTime()` inside an audio-adjacent path) becomes a compile
  error, not a runtime surprise — the flip is compiler-enumerated (the slice-44/45 cascade recipe).
  Off-main callers get async variants or snapshots; **never** `assumeIsolated` in playback paths.
- **Behavior shifts to next-runloop** for hopped callbacks. Finish/fail/duration events already
  arrive asynchronously from AVFoundation; ordering within the main actor is preserved.
- **The flip must be one PR** (plus preparatory seam PRs): a half-isolated PlaybackManager is worse
  than either endpoint.

### D3. Engines keep their confinement; `PlaybackProtocol` de-`@objc`'d later

`DefaultPlayer`/`EffectsPlayer` remain `@unchecked Sendable` with their queue/lock confinement — they
are the real-time boundary owners. `PlaybackProtocol` being `@objc` forces class conformers and
blocks protocol isolation annotations; de-`@objc`ing it is a small standalone PR (no ObjC callers)
once the delegate-callback hops land.

### D4. Position tracking is redesigned so `Episode` can become a value type

The Phase 3 verdict: `Episode`/`UserEpisode` cannot become structs while
`PlaybackManager.progressTimerFired` mutates `episode.playedUpTo` in place ~1/sec and `PlaybackQueue`
caches a live `topEpisode` reference. The fix is ownership, not synchronization:

- New `PlaybackPositionTracker` (a `@MainActor` type owned by PlaybackManager): owns the *current*
  episode's transient position (`playedUpTo`, tick counter), applies the every-30-ticks DB save, and
  publishes position via the existing notification. The `Episode` object stops being the mutable
  channel; UI reads position from the tracker (or the notification payload), not from a shared
  episode instance.
- `PlaybackQueue.topEpisode` becomes a value snapshot refreshed on queue changes (it already
  re-caches on every mutation).
- `EpisodeDataManager.saveEpisode`-style side-effect mutation of passed-in episodes was already
  removed in Phase 3's return-the-saved-value sweep.

### D5. `BaseEpisode` de-`@objc` is the struct-conversion gate — and it is feasible

The survey confirms **no KVO on episode objects** and no ObjC-side conformers; the `@objc` is legacy
bridging. Sequence: re-express `BaseEpisode` as a plain Swift protocol (~53 cast sites to revisit,
mostly `as? BaseEpisode` params), fix ObjC helpers (`SJMediaMetadataHelper`, `MNAVChapterReader`) to
take the primitives they need instead of the model. Then `UserEpisode` → struct, then `Episode` →
struct, following the proven Folder/EpisodeFilter/Podcast recipe (footguns already documented: id
back-population after save, mutate-then-save helpers must return, test mocks write back).

### D6. Narrow the public surface opportunistically, not exhaustively

485 call sites is too many to re-route wholesale. What we do take: the 43 direct
`PlaybackManager.shared.queue.…` sites get forwarding methods (stops leaking `PlaybackQueue`), and
App-Intents/background callers standardize on `PlaybackFacade`. A full protocol+DependencyKey for the
whole surface is *not* a Phase 5 goal; `@MainActor` isolation gives the safety payoff without the
485-site churn.

### D7. VoiceBoostN

The C DSP stays C (real-time). The `voiceBoostN` feature flag is TestFlight-only and needs the usual
remote-config sign-off before retirement — out of scope here; the flag reads on the render path are
snapshot into `AtomicBool`s already.

## Slice sequence

| # | Slice | Size | Contents |
|---|---|---|---|
| 1 | **This plan** | doc-only | Commit the design + inventory |
| 2 | Queue encapsulation | S | Forward the 43 `.queue` call sites through PlaybackManager methods |
| 3 | Callback hops | M | `AudioPlayTask`/`DefaultPlayer`/`EffectsPlayer` `playerDid*` calls become `Task { @MainActor }` hops; `requiredStartingPosition` becomes a load-time snapshot |
| 4 | Helper isolation | S | `ChapterManager`, `SleepTimerManager`, `FadeOutManager`, `Debounce`, `BackgroundShakeObserver` → `@MainActor` |
| 5 | **The flip** | L | `PlaybackManager` + `PlaybackQueue` → `@MainActor`; delete `@unchecked Sendable`, boxes, and bridges; async variants/hops for the off-main caller tail (compiler-enumerated) |
| 6 | `PlaybackProtocol` de-`@objc` | S | Plain Swift protocol; annotate the callback surface |
| 7 | Position tracker | M | `PlaybackPositionTracker`; `topEpisode` snapshotting; stop in-place `playedUpTo` mutation |
| 8 | `BaseEpisode` de-`@objc` | M | Plain protocol; fix ObjC helper signatures; revisit cast sites |
| 9 | `UserEpisode` → struct | L | Phase 3 recipe |
| 10 | `Episode` → struct | L | Phase 3 recipe; heaviest, last |
| 11 | Cleanup | S | Remove stale rationales; repurpose the empty concurrency gate to enforce baseline-stays-zero; update MODERNIZATION.md |

Verification per slice: clean build-for-testing under Swift 6, full `PocketCastsTests` +
`PocketCastsDataModelTests` suites, `check:static`, plus manual playback QA notes on the risky slices
(5, 7, 9, 10): play/pause/seek/skip during stream and download, effects toggle, sleep timer fade,
route change (headphones), interruption (call), background→foreground, Up Next reorder, chapter skip.

## What Phase 5 does *not* do

- No rewrite of the audio engines or the C DSP; the real-time boundary is kept, narrowed, documented.
- No app-wide `PlaybackManager` facade adoption (485 sites) — isolation, not indirection, is the goal.
- No `voiceBoostN`/`effectsPlayerQOSUpgrade` flag retirement without remote-config sign-off.
