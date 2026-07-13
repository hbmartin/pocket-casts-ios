# Playback Power-User Features — Implementation Plan

## Context

1. **One-Tap Play** — tapping an episode row plays it immediately instead of opening the detail sheet (global toggle).
2. **Seek Acceleration** — repeated skip taps within a short window grow the skip interval (×1→×2→×4).
3. **Headphone next/previous episode** — new headphone-control actions that jump episodes in Up Next.
4. **Smart Resume** — snap the intelligent-resumption rewind target to a nearby silence between words, reusing the AdvancedAudio DSP utilities.
5. **Stop After This Episode** — first-class player-shelf action over the existing `numberOfEpisodesToSleepAfter == 1` mechanism.

## User decisions (settled)

- **Detail access with One-Tap Play on:** new "Details" swipe action on episode rows; long-press stays multi-select.
- **Settings storage:** synced style — `@ModifiedDate` AppSettings fields + `SyncSettingsTask` wiring + protobuf update.
  - Constraint discovered: `api.pb.swift` is generated from `api.proto` in Automattic's **private** pocketcasts-api repo (the root `sync_api.proto` is the Android record-sync contract and does not contain `ChangeableSettings`). True regeneration is impossible from this fork → hand-edit the checked-in generated file `Modules/Sources/PocketCastsServer/Private/Protobuffer/api.pb.swift`, adding `Api_BoolSetting` fields with fork-reserved field numbers (1001+). Caveat: the production server will drop unknown fields, so these settings won't round-trip cross-device until the server knows them; local behavior and upload are unaffected.
  - Feature 3 needs **no proto change** — headphone actions already sync as Int32 (fields 61/62); we only add new enum raw values (5, 6).
- **Previous-episode semantics:** music-player convention — >~15s into episode → restart from 0; within first ~15s → jump to prior episode from an in-memory session history (fallback: restart).
- **Stop After Episode scope:** shelf action only; no global setting.

## Key existing code to reuse

| What | Where |
|---|---|
| Tap-to-play template (toggle + branch + `will_play` analytics) | `podcasts/UpNextViewController+Table.swift:138-149` (`Settings.playUpNextOnTap()`) |
| Canonical play call | `PlaybackActionHelper.play(episode:playlistUuid:podcastUuid:playlist:)` — `podcasts/PlaybackActionHelper.swift:9` |
| Synced-setting exemplar (all 5 touch points) | `playUpNextOnTap`: `AppSettings.swift:23`, `Settings.swift:362-375`, `AppSettings+ImportUserDefaults.swift:19`, `SyncSettingsTask.swift:18,74`, api.pb.swift field |
| General-settings toggle row pattern | `podcasts/GeneralSettingsViewController.swift:15,17,229-236,465-466,580-584` |
| Skip methods | `podcasts/PlaybackManager.swift:500-525`; remote dispatch `handleRemoteAction` :2482-2516 |
| Up Next jump | `PlaybackManager.switchToPlaying(upNextIndex:)` :836; `PlaybackQueue.insert/episodeAt` |
| Headphone enums | `HeadphoneControlAction` `Constants.swift:375`; `HeadphoneControl: Int32` `ServerEnums.swift:42`; mapping `Settings.swift:1478-1508` |
| Resume tiers | `podcasts/PlaybackCatchUpHelper.swift`; applied via `requiredStartingPosition()` `PlaybackManager.swift:1163-1181` |
| Offline PCM reading recipe | `podcasts/AdvancedAudio/EpisodeLoudnessScanner.swift:42-88`; `AudioUtils.calculateRms` `podcasts/AudioUtils.swift:47` |
| Sleep-after-episode mechanism | `PlaybackManager.numberOfEpisodesToSleepAfter` :167-176, end-stop :1355-1360 |
| Player shelf actions | `PlayerAction` `Modules/.../Enums.swift:291-304` + `podcasts/Enumerations.swift:255-489`; shelf `NowPlayingPlayerItemViewController+Shelf.swift` |

## Feature plans

### Shared: adding a synced bool setting (used by Features 1 & 2)

Five touch points, cloning `playUpNextOnTap`:
1. `Modules/Sources/PocketCastsServer/Public/AppSettings.swift` — `@ModifiedDate public var <name>: Bool = false` (inline default; no `defaults` factory change).
2. **Hand-edit `Modules/Sources/PocketCastsServer/Private/Protobuffer/api.pb.swift`** — add an `Api_BoolSetting` field to BOTH `Api_ChangeableSettings` (struct :327, impl :8766) and `Api_NamedSettingsResponse` (struct :2103, impl :10250). Do NOT touch legacy `Api_NamedSettings` (:1215). Fork-reserved field numbers: **1001 = tap_to_play, 1002 = seek_acceleration**. Seven edits per message, tagged `// FORK:`:
   - accessor block (get/set + `has`/`clear`) after `playUpNextOnTap`'s (:586-593 template)
   - `_StorageClass` var, `init(copying:)` line
   - `_protobuf_nameMap` bytecode: insert after `listening_time_stats\0` — instruction `\u{4}` (standardDelta) + 6-bit-varint delta (bit 0x40 = continuation; verified against `BytecodeReader.swift` in the swift-protobuf checkout). Delta 901 (1001−100) encodes as `E\u{e}` → `\u{4}E\u{e}tap_to_play\0`; then 1002 immediately after as standardNext (+1): `\u{3}seek_acceleration\0`. **Mandatory**: missing nameMap entry crashes the `try! ...jsonString()` at `SyncSettingsTask.swift:136`. Fallback if bytecode proves fragile: legacy dictionary `_NameMap` initializer still compiles (`#if !REMOVE_LEGACY_NAMEMAP_INITIALIZERS`). The jsonString guard test below fails loudly on any mistake.
   - `decodeMessage` case (`case 1001: ... decodeSingularMessageField`), `traverse` visit **after field 100** (ascending order), `==` check.
3. `SyncSettingsTask.swift` — upload `x.update(settings.$x)` (:18 area); download `$x.update(setting: settings.x)` (:74 area). Merge safety verified: server stripping unknown fields returns epoch `modifiedAt` → local value preserved.
4. `podcasts/Settings.swift` — bridge with `FeatureFlag.newSettingsStorage` branch + UserDefaults key (template :362-375).
5. `podcasts/AppSettings+ImportUserDefaults.swift` — import line.

Guard test: `Api_ChangeableSettings` with field set → `try jsonString()` succeeds and contains the camelCase name (regression guard for the bytecode edit). Extend `Modules/Tests/PocketCastsServerTests/SyncSettingsTaskTests.swift` request/response round-trips.

### Feature 1: One-Tap Play

Settings: synced bool `tapToPlay` per shared recipe (field 1001, key `SJTapToPlay`).

**General settings UI** (`podcasts/GeneralSettingsViewController.swift`): `tapToPlay` in `TableRow` (:15), own section after `[.playUpNextOnTap]` (:17) for its footer, SwitchCell case cloning :229-236, on/off footer strings (:459 switch), handler + `Settings.trackValueToggled(.settingsGeneralTapToPlayToggled,...)` cloning :580-584. New analytics cases in `AnalyticsEvent.swift`: `settingsGeneralTapToPlayToggled`, `episodeTapped`. L10n keys: `settings_general_tap_to_play`, `..._on_subtitle`, `..._off_subtitle`, `episode_details` ("Details"); regenerate SwiftGen strings.

**didSelectRowAt branch** (template = Up Next `UpNextViewController+Table.swift:138-149`), inside the existing non-multi-select else path; multi-select/long-press untouched:
```swift
let playOnTap = Settings.tapToPlay()
Analytics.track(.episodeTapped, properties: ["source": analyticsSource, "will_play": playOnTap])
if playOnTap {
    AnalyticsPlaybackHelper.shared.currentSource = analyticsSource
    PlaybackActionHelper.play(episode: episode, playlist: <screen playlist>)
    return
}
presentEpisodeDetails(for: episode)  // extracted existing construction
```
Per screen: PodcastViewController+TableData (allEpisodesSection branch, `.podcast(uuid:)`, keep `hideSearchKeyboard()`); PlaylistDetailViewController+TableView (AFTER the `wasDeleted` guard :228-243, `.filter(uuid:)`, no analyticsSource property — use "filters"); DownloadsViewController+Table (AFTER `downloadFailed()` retry branch :99-111, `.downloads`); ListeningHistoryViewController+Table (`nil` playlist); StarredViewController+Table (`.starred`); UploadedViewController+Table (`.files`, UserEpisode → `PlaybackActionHelper.play` handles it). Up Next and search stay as-is.

**"Details" swipe action** — swipe infra is SwipeCellKit via shared builder `podcasts/Episode Cells/SwipeActionsHelper.swift`; all six screens implement `SwipeHandler` in per-screen `+Swipe.swift`:
1. Add `showDetails(episode:at:)` to `SwipeHandler` protocol (:35-45).
2. In `createRightActionsForEpisode` (:110), append a Details `TableSwipeAction` gated on `Settings.tapToPlay()` — **append LAST, never index 0** (right-orientation `expansionStyle = .destructive` full-swipe triggers `actions[0]` = archive/delete). Also add in the UserEpisode branch (:117-124); keep `wasDeleted` branch delete-only. Color `ThemeColor.support01()` (only unused swipe swatch); icon: new `stop`-style imageset or `episode-circle`.
3. Add `case details` to fileprivate `SwipeActions` enum (:196) → flows through existing `.episodeSwipeActionPerformed`.
4. Per-screen `showDetails` calls the extracted `presentEpisodeDetails(for:)` (one source of truth per screen; a shared protocol isn't worth it — constructions differ in init overload/source/playlist).

Tests: `SettingsTests` round-trip (both storage modes); SyncSettingsTask + nameMap JSON tests per shared recipe.

### Feature 2: Seek Acceleration

Settings: synced bool `seekAcceleration` per shared recipe (field 1002, key `SJSeekAcceleration`, default false).

**New file `podcasts/SeekAccelerationTracker.swift`** (root `podcasts/` is a classic group → 4 pbxproj entries mirroring `PlaybackCatchUpHelper.swift` at :393/:1374/:3271/:5908, main app target only). Pure struct, injectable `now:` for tests:
- `amount(for direction: .back/.forward, baseAmount:, now: Date = Date()) -> TimeInterval` — if last tap was same-direction and within `window` (1.5s): `multiplier = min(multiplier * 2, 4)`, else reset to 1; returns `baseAmount × multiplier`.
- `reset()` clears streak.

**PlaybackManager wiring** (`podcasts/PlaybackManager.swift`):
- `private var seekAcceleration = SeekAccelerationTracker()` near `catchUpHelper` (:199).
- Public `skipBack()`/`skipForward()` (:500-525) apply the tracker when `Settings.seekAccelerationEnabled()`; **private `skipBack(amount:)`/`skipForward(amount:)` untouched** so explicit-interval callers (Siri "skip N seconds" via `MPSkipIntervalCommandEvent` at :1957/:1972/:2118/:2148) never accelerate. `StatsManager.addSkippedTime(amount)` (:524) automatically records the accelerated amount.
- Streak resets: pass `seekHint: .forward` in `skipForward(amount:)` (:522; `.back` already passed; `.forward` case exists unused at :637-640) and in `seekTo(...)` (:642) do `if seekHint == nil { seekAcceleration.reset() }` — covers scrubber, chapter jumps, bookmark/sync seeks with no call-site churn. Explicit `reset()` in `pause()` (:464), `load(episode:)` (:356), `playNextEpisode` (:844), `endPlayback` (:929).
- All callers funnel through the public methods (player/mini/video buttons, shortcuts, Siri facade, `skipFromRemote`, command-center no-interval fallbacks) → all accelerate; no double application. 0.2s remote debounce coexists with the 1.5s window.

**Settings UI**: `seekAcceleration` TableRow right after `.skipBack` in `GeneralSettingsViewController` tableData; SwitchCell + handler + `Settings.trackValueToggled(.settingsGeneralSeekAccelerationToggled,...)`; L10n `settings_general_seek_acceleration` ("Skip Acceleration"). Footer only if given its own section (footer keys off last row).

Tests: new `PocketCastsTests/Tests/Playback/SeekAccelerationTrackerTests.swift` (auto-synced test group) — base amount first tap, ×2/×4 progression, cap, window expiry, direction-change reset, `reset()`, boundary (`<=` window). Proto guard per shared recipe.

### Feature 3: Headphone next/previous episode

**Enums** (no proto change — headphone actions sync as existing Int32 fields 61/62):
- `HeadphoneControlAction` (`podcasts/Constants.swift:375-390`): add `nextEpisode`, `previousEpisode` (JSONCodable by case name; old builds decode-fail → `SettingValue` default, safe).
- `HeadphoneControl: Int32` (`ServerEnums.swift:42-48`): `nextEpisode = 5`, `previousEpisode = 6` (fork-invented values — document cross-platform caveat at the enum).
- Mapping both directions in `Settings.swift:1478-1508` (compiler-enforced exhaustive). `analyticsDescription` in `podcasts/Bookmarks/Bookmarks+Analytics.swift:38-53`: `"next_episode"`/`"previous_episode"`.
- `HeadphoneSettingsViewController.swift:37`: `[.skipForward, .nextChapter, .nextEpisode, .skipBack, .previousChapter, .previousEpisode, .addBookmark]`; titles: `L10n.nextEpisode` **already exists** (Localizable.strings:1349), add `"previous_episode" = "Previous Episode";`. `iconName` stays nil (all cases nil today).

**New file `podcasts/PlayedEpisodeHistory.swift`** (4 pbxproj entries): in-memory stack of UUIDs, capacity 20, consecutive-dedupe, `record/popPrevious/removeAll`.

**PlaybackManager** (`private var episodeHistory`, `private var isNavigatingBackInHistory = false`):
- Record outgoing episode in `load(episode:)` AFTER the `switchTo` early-return block (:362-368) to avoid double-recording, guarded on `episodeIsChanging && !isNavigatingBackInHistory`; and in `playNextEpisode` (:844) immediately before `queue.removeTopEpisode()` (that path bypasses `load`).
- `func skipToNextEpisode()`: guard `queue.upNextCount() > 0` else no-op + FileLog (chosen over skip-forward fallback); track `.playbackNextEpisode`; `playNextEpisode(autoPlay: true)` (private, same file). Note: decrements `numberOfEpisodesToSleepAfter` and respects shuffle — acceptable, matches "episode ended" semantics.
- `func skipToPreviousEpisodeOrRestart(restartThreshold: TimeInterval = 15)`: if `currentTime() > 15` → `seekTo(time: 0)`; else pop history → `DataManager.findBaseEpisode` → set `isNavigatingBackInHistory`, `queue.insert(episode:, position: 0)` + `switchToPlaying(upNextIndex: 0)` (current episode lands at Up Next front via `pushNewCurrentlyPlaying`, so "next" returns to it), clear flag. Fallback restart if no usable history. **Deliberately avoids `load(episode:)`**: with empty Up Next, `load` hits `queue.overrideAllEpisodesWith` (:380-381) which drops the current episode instead of re-queueing it.
- `handleRemoteAction` (:2482-2505): append `.nextEpisode`/`.previousEpisode` cases LAST (existing fallthrough chains are order-sensitive), each guarded by a small `debounceRemoteEpisodeSkip(_:)` helper reusing `lastSeekTime` + `minTimeBetweenRemoteSkips` (duplicate nextTrack events would otherwise skip two episodes). Optionally refactor `skipFromRemote` onto the helper.
- `updateCommandCenterSkipTimes` (:2097-2159): mirror the existing chapter hijack (:2103-2114/:2133-2144) for episode actions — when the headphone action is `.nextEpisode`/`.previousEpisode` and the event interval matches the configured skip time, route to `handleRemoteAction`; interval mismatch (Siri custom skip) passes through.
- previous/nextTrackCommand registration (:1951-1979): no changes — already routes through `handleRemoteAction`. Set `analyticsPlaybackHelper.currentSource = commandCenterSource` before dispatch (no `.headphones` AnalyticsSource exists; established source for this path).
- New analytics events: `playbackNextEpisode`, `playbackPreviousEpisode` next to `playbackSkipBack/Forward` (`AnalyticsEvent.swift:221-222`).

No migration: defaults stay `.skipBack`/`.skipForward`.

Tests: `PlayedEpisodeHistoryTests` (order, dedupe, capacity); enum round-trip (`HeadphoneControl(action:).action` for all cases, raw 5/6 stability, JSONCodable encode/decode of new cases).

### Feature 5: Stop After This Episode (shelf action)

1. `PlayerAction` case `stopAfterEpisode = "stopAfterEpisode"` (`Modules/.../Enums.swift:291-304`). `podcasts/Enumerations.swift`: `defaultActions` after `.sleepTimer` (lands in overflow — `maxShelfActions = 4`; `Settings.playerActions()` :718 appends missing defaults for existing users); `intValue` **14** (13 is current max; 7 is retired — don't reuse); `title` `L10n.playerActionTitleStopAfterEpisode`; icon = new imageset (NOT `sleep-menu` — indistinguishable from Sleep Timer); `canBePerformedOn` true; `analyticsDescription` `"stop_after_episode"`.
2. `NowPlayingPlayerItemViewController+Shelf.swift`: delegate method `stopAfterEpisodeTapped()`; `loadActionIntoShelf` case mirroring sleep-timer button (:74-83, minus animation) with active tint when `numberOfEpisodesToSleepAfter > 0`; handler semantics (simplest safe): active means `numberOfEpisodesToSleepAfter > 0`; tap while active → `cancelSleepTimer(userInitiated: true)` + `.playerSleepTimerCancelled`; else `numberOfEpisodesToSleepAfter = 1` + `.playerSleepTimerEnabled {time: end_of_episode}` — the `didSet` (:167-176) already clears any time-based timer, identical to the sleep panel path (auto-restart-within-5-min side effect accepted, consistent with sleep timer).
3. **`ShelfLoadState` fix**: add `stopAfterEpisodeOn: Bool` to `updateRequired` (+ stored var), passed from `reloadShelfActions()` (:36) — otherwise the button won't re-tint when a time timer converts to episode-stop (`sleepTimerActive()` stays true). Update propagation via existing `sleepTimerChanged` → `reloadShelfActions()` (`+Update.swift:23`).
4. Overflow: `ShelfActionsViewController+Table.swift` `didSelectRowAt` case (:91-116) + active-tint condition (:50).
5. Sync tolerance confirmed — **no proto change**: `playerShelf` is `[ActionOption]` (`Option<PlayerAction,String>`); unknown raw values round-trip losslessly on old iOS clients; legacy int path compactMap-drops 14 safely. Android/Web unknown-id tolerance is an assumed risk.
6. L10n: `player_action_title_stop_after_episode`, `player_accessibility_stop_after_episode_on`. Analytics: reuse existing events only.
7. Tests: **must update** hardcoded `defaultPlayerActions` in `SettingsTests` (:13-29, else assertions at 96/108/126 fail); add PlayerAction int/raw round-trip stability test asserting `.stopAfterEpisode.intValue == 14`.

### Feature 4: Smart Resume — snap resume to inter-word silence

**Architecture: precompute at pause time** (not at resume). Decisive facts: `requiredStartingPosition()` runs on the **main thread** for the DefaultPlayer path (`DefaultPlayer.swift:904-917`), so synchronous decode at resume would block play-start; and the rewind tiers only fire ≥5 min after pause, so a ~100ms background analysis at pause always finishes in time. Existing uuid/`lastPausedAt` guards in `adjustStartTimeIfNeeded` (`PlaybackCatchUpHelper.swift:15`) validate stored candidates for free. **No changes to PlaybackManager, EffectsPlayer, AudioReadTask, or DefaultPlayer.**

New files (both dirs are `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits):
- `podcasts/AdvancedAudio/SilenceGapFinder.swift` — pure `nonisolated struct`, no AVFoundation: `snapTime(levelsDB:[Float], windowStart:, hopDuration:, target:, parameters:) -> TimeInterval?`. Algorithm: 10th/90th percentile → noise floor/speech level; refuse if dynamic range < 12dB (music guard, matches `TrimTuning.adaptiveOffsetDB`); threshold = floor + 0.3×range; gaps = runs of ≥3 hops (150ms) below threshold with a real onset after them; snap = `max(gapStart, onset − 0.15s)`; candidates within [T−2.5s, T+0.5s]; pick nearest to T, ties → earlier. Params struct defaults: windowBefore 2.5s, windowAfter 0.5s, hop 50ms, minGap 150ms, onsetPad 150ms, maxAdjustment 2.5s.
- `podcasts/AdvancedAudio/ResumeSnapAnalyzer.swift` — `protocol ResumeSnapAnalyzing: Sendable` + `final class ResumeSnapAnalyzer` on serial `.utility` queue (mirror `EpisodeLoudnessScanner:19`): opens `AVAudioFile(forReading:)` Float32 deinterleaved, seeks `framePosition` per tier target, reads window into one buffer (~1.2MB max), per-50ms-hop RMS via `AudioUtils.calculateRms` → dB; internal synchronous `snappedTimes(in:targets:)` for tests. `[SmartResume]` FileLog tags.

Modified: `podcasts/PlaybackCatchUpHelper.swift`
- `init(analyzer: ResumeSnapAnalyzing = ResumeSnapAnalyzer(), defaults: UserDefaults = .standard)` — zero-arg construction at `PlaybackManager.swift:199` keeps compiling.
- `playbackDidPause`: clear old candidates dict unconditionally; guard intelligentResumption + `episode.downloaded(pathFinder:)` + `!episode.videoPodcast()` + `playedUpTo > 10`; compute candidates for targets `[t−10, t−15, t−30].filter { $0 > 0 }`; in completion **re-check stored uuid/playedUpTo still match** before persisting dict `"lastPauseSnapCandidates"` = `{uuid, playedUpTo, "10": snap, "15": snap, "30": snap}`.
- `adjustStartTimeIfNeeded`: each tier branch returns `snappedIfValid(raw:tierSeconds:...)` — validates dict (uuid+position match, `|snap−raw| ≤ 2.5s`, `≥ 0`), logs snap or raw fallback.

Behavior matrix: snap applies on downloaded episodes via both players (EffectsPlayer `pendingStartingPosition`→`AudioReadTask.framePosition`; DefaultPlayer zero-tolerance seek). Streaming/video/seek-then-play (`seekingTo` short-circuit at `PlaybackManager.swift:1166-1171`)/fresh-start/<5min-resume → raw behavior unchanged. VBR seek error (~23ms) and AVPlayer priming skew absorbed by the 150ms onsetPad; trim-silence may trim the snapped gap — acceptable (word starts immediately).

Tests (new dir `PocketCastsTests/Tests/Playback/SmartResume/`):
- `SilenceGapFinderTests` — synthetic dB arrays (pattern: `TrimSilenceDetectorTests.swift:15-26`): gap detection, min-gap rejection, low-dynamic-range nil, nearest/tie-earlier, +0.5s boundary, end-run discard.
- `ResumeSnapAnalyzerTests` — synthesize WAV via `AVAudioFile(forWriting:)` in temp dir (440Hz bursts, 300ms silences at known times); assert snaps within ±60ms; stereo + near-0 + continuous-tone cases.
- `PlaybackCatchUpHelperTests` (first ever) — injected `UserDefaults(suiteName:)` + mock analyzer: persistence guard, tier lookup per elapsed time, raw fallback, dict cleared on new pause, setting-off → analyzer never called.

## Environment facts (verified, shape the implementation)

- `FeatureFlag.newSettingsStorage`/`.settingsSync` are **hard-off on this fork** (`FeatureFlag.swift:108-110` `shouldEnableSyncedSettings = false`) → live read path for all new settings is UserDefaults; the synced plumbing is wired but dormant (same duality as upstream `playUpNextOnTap`). Sync tests still exercise the proto edits.
- pbxproj: `PocketCastsTests/`, `podcasts/AdvancedAudio/` (and several others) are `PBXFileSystemSynchronizedRootGroup` → new files there need **no project edits**. Root `podcasts/` is a classic group → `SeekAccelerationTracker.swift` and `PlayedEpisodeHistory.swift` each need 4 pbxproj entries (mirror `PlaybackCatchUpHelper.swift` entries at :393/:1374/:3271/:5908).
- `PlaybackManager` is `@MainActor`; all remote-command targets and `handleRemoteAction` already run in that isolation.

## Implementation order (one slice commit per feature, matching branch convention)

1. **F2 Seek Acceleration** — tracker + PlaybackManager wiring + local setting + UI (usable immediately, flags off) → then synced plumbing incl. api.pb.swift fields 1001+1002 **in one edit pass** (both fields at once keeps the nameMap deltas simple) + proto guard tests.
2. **F1 One-Tap Play** — settings bridge (proto already done in step 1) + per-screen tap branches + Details swipe action + settings UI.
3. **F3 Headphone episode actions** — enums/mapping/picker + history + PlaybackManager actions + remote dispatch.
4. **F5 Stop After Episode** — PlayerAction case + shelf/overflow + ShelfLoadState fix.
5. **F4 Smart Resume** — SilenceGapFinder → ResumeSnapAnalyzer → PlaybackCatchUpHelper wiring, tests at each step.

Run `mise run format` and `mise run check:static` per slice; consider a Semgrep rule if the api.pb.swift hand-edit pattern proves error-prone (per CLAUDE.md guidance).

## Key risks

- **api.pb.swift bytecode nameMap edit** is the riskiest single change: a wrong byte hits a precondition at first use; a missing entry crashes the `try!` at `SyncSettingsTask.swift:136`. Guard: jsonString unit test; fallback: legacy dictionary `_NameMap` initializer. Consider softening the `try!` to `(try? ...) ?? "<encoding failed>"` as defense-in-depth.
- Production server ignores fork fields 1001/1002 and `HeadphoneControl` 5/6 — settings are effectively device-local until a server fork accepts them; merge logic verified safe both directions.
- SwipeCellKit: Details action must never be `actions[0]` on the right orientation (full-swipe expansion = destructive action).
- `SettingsTests` hardcoded `defaultPlayerActions` must be updated with F5 or three existing assertions fail.
- Lock-screen ±skip buttons change meaning when an episode action is selected (same tradeoff the chapter actions already made); AirPods double/triple-tap works regardless.

## Verification

- **Unit**: `mise run test:staging` (app tests incl. new SeekAccelerationTracker/PlayedEpisodeHistory/SmartResume/Settings tests); `ONLY_TESTING=PocketCastsServerTests mise run test:staging` for SyncSettingsTask + nameMap guard tests. Use `SIMULATOR_OS=26.5`.
- **Simulator walkthrough** (build via CLAUDE.md staging recipe):
  - F1: toggle off → row tap opens detail, no Details swipe; toggle on → tap plays on all six screens (streaming warning honored, archived un-archives, already-playing resumes), long-press still multi-selects, swipe shows Details last, full-swipe still archives.
  - F2: toggle on, tap skip-forward 3× fast on full player → +45/+90/+180 (watch time label/FileLog); pause/scrub/2s wait → resets to +45. Siri "skip forward 2 minutes" still exactly 2 min.
  - F3: set headphone Next/Previous to episode actions; lock-screen/Control Center next jumps episode (empty Up Next → no-op + FileLog); previous >15s in → restart; <15s → prior episode with old one at Up Next front.
  - F5: player overflow shows "Stop After This Episode"; arm → active tint; episode end → playback stops, state clears; interactions with running time-based and multi-episode sleep timers per plan semantics.
  - F4: download episode, pause mid-sentence, check `[SmartResume] candidates` log; resume after >5 min (or locally lowered tier) with trim-silence off and on → log shows snap, audio starts at word boundary; streamed episode and seek-then-play → raw behavior.

---

## Session reconciliation notes (added 2026-07-12 when this plan was queued; the plan text above is verbatim as provided)

Written against a pre-session snapshot of the tree; these anchors have since changed on `local-first-program`:

1. **`PlaybackActionHelper.play` signature changed (F3 SiriKit removal, this session):** now `play(episode: BaseEpisode, playlist: AutoplayHelper.Playlist? = nil)` — the `playlistUuid:`/`podcastUuid:` donation parameters were deleted along with SiriKit. The One-Tap Play snippet's `playlist:` argument maps to `AutoplayHelper.Playlist` (`.podcast(uuid:)`, `.filter(uuid:)`, `.downloads`, `.starred`, `.files`, nil) — the per-screen list above remains correct; only the call shape changed (simpler).
2. **`SiriShortcutsManager` and the SiriKit stack no longer exist**; `HeadphoneSettingsViewController` still uses `L10n.siriShortcutNextChapter/PreviousChapter` strings (deliberately retained). Feature 3's picker work is unaffected.
3. **Line numbers throughout are stale** — this session ran large sweeps (typed notifications, PlaylistQueryBuilder rewrite, theme codegen). Re-locate every `:NNN` anchor by symbol, not line.
4. **`numberOfEpisodesToSleepAfter`, skip methods, `handleRemoteAction`, catch-up tiers**: PlaybackManager was touched by B5 (autoplay query :900 → typed request) and carries F3 edits; semantics unchanged.
5. **A6a queued**: `shouldEnableSyncedSettings` flips to `true` later this session (program item A6a). If that lands first, the live read path for new settings becomes the synced storage, not UserDefaults — the dual wiring in this plan handles both; just don't rely on the "hard-off" fact when writing tests.
6. **`podcasts/Notifications/` message conventions**: if any feature posts notifications, prefer the typed `MainActorMessage` structs (see `EpisodeMessages.swift`) — Phase 5 sweeps are converting string posts domain-by-domain.
7. **Queue position**: runs after the AI UX Improvements plan (#24) per arrival order — program remainder → transcription → smart playlists → auth hardening → AI UX → this plan.
