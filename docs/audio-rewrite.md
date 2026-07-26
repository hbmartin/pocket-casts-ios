# Audio DSP Overhaul + Advanced Audio Tuning Settings

## Context

The audio engine has several algorithmic weaknesses identified in review: the trim-silence gate uses a fixed RMS threshold with no adaptive noise floor, no hysteresis, buffer-count (not time) based constants, and audible fade-dip splices; VoiceBoostN's "true-peak" limiter is actually sample-peak, its soft-knee and adaptive-smoothing constants are dead code, LUFS is measured on channel 0 only, and gain adapts slowly from scratch on every episode start/seek; the legacy volume-boost chain sounds different between the two players (PreGain 11 + dynamics processor vs PreGain 8 without); time-stretch uses the old `AUiPodTimeOther` unit with no alternative; and sub-0.5× speeds silently snap to 1.0×.

This change implements all of it, plus an always-visible **Settings → Advanced Audio** screen exposing ~35 DSP parameters for live tuning by ear.

**User decisions:** streaming DSP (EffectsPlayer tail-follow) is DEFERRED; settings row always visible, no feature flag; ALL three discriminator modes (RMS / heuristic / system VAD) selectable; parameter changes apply LIVE to the running player.

**Hard rule: all `AudioTuning` defaults must reproduce current behavior bit-for-bit** (crossfade 0 ms = legacy fade splice, knee 0 dB = hard knee, true-peak off, hysteresis/hold 0, adaptive floor off, discriminator .rms, algorithms unchanged).

## Verified grounding

- App target: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; audio classes are `nonisolated final class … @unchecked Sendable` (AudioReadTask pattern).
- `EngineStateMirror` (podcasts/PlaybackManager.swift:37-67): NSLock-guarded snapshot read by audio threads. Extend it.
- Trim constants (podcasts/AudioReadTask.swift:364-399): minRMS 0.0055/0.00511/0.005 (≈ −45.2/−45.8/−46.0 dBFS), gap 20/16/4 buffers, re-insert 14/12/0 buffers, buffer = 1152 frames (≈26.12 ms @44.1k), max stash 1000, 5 s end guard.
- `FeatureFlag.voiceBoostN` defaults false (TestFlight-gated); `DefaultPlayer.tapProcess` reads `Settings.isVoiceBoostNEnabled` (UserDefaults!) per tap callback — fix via mirror-cached flag.
- Latest DB migration = 76 (Modules/Sources/PocketCastsDataModel/Private/Managers/Util/DatabaseHelper.swift:66). New column ⇒ migration 77 **and** both baked `CREATE TABLE` blocks (SJEpisode ~line 280, SJUserEpisode ~line 399).
- `cachedFrameCount` blueprint: DataManager.swift:741-755, EpisodeDataManager.swift:544-549 (+ column arrays line 34), EpisodeRepository.swift:52, Episode+fromDatabase.swift, consumed EffectsPlayer.swift:123-131.
- PocketCastsTests is app-hosted (`TEST_HOST`/`BUNDLE_LOADER`), no own bridging header — C symbols resolve against host binary but decls need a test bridging header.
- SwiftGen strings regenerated manually via `mise run generate:code`.
- Root-level `podcasts/*.swift` need explicit pbxproj refs; new dir `podcasts/AdvancedAudio/` registered once as a `PBXFileSystemSynchronizedRootGroup` (copy `Syncing` pattern) makes all new files drop-in.
- SnapshotTests (SPM) cannot reach app-target views — no snapshot test for the new screen; skip.

---

## Phase 1 — Foundation: `AudioTuning` + Settings + mirror plumbing

**New `podcasts/AdvancedAudio/AudioTuning.swift`** (all types `nonisolated struct … Codable, Equatable, Sendable`):

```swift
nonisolated struct AudioTuning: Codable, Equatable, Sendable {
    var version: Int = 1
    var trim = TrimTuning(); var voiceBoost = VoiceBoostTuning(); var timeStretch = TimeStretchTuning()
    static let `default` = AudioTuning()
}
```

Field tables (default / range / step — defaults = current constants):

**TrimTuning** — `useCustomGate` Bool false (presets win when false); `thresholdDB` −45.8 (−70…−20, 0.5); `adaptiveNoiseFloor` Bool false; `adaptiveOffsetDB` 12 (3…24, 1); `adaptiveWindowSeconds` 10 (5…30, 1); `hysteresisDB` 0 (0…12, 0.5); `holdTimeMs` 0 (0…500, 10); `minGapMs` 418 (0…1500, 25); `keepGapMs` 313 (0…1000, 25); `crossfadeMs` 0 (0…200, 5; 0 = legacy fade splice); `endGuardSeconds` 5 (0…30, 1); `maxGapHoldSeconds` 26 (5…60, 1; today's 1000-buffer cap); `discriminator` enum .rms/.heuristic/.vad = .rms; heuristic tunables: `flatnessThreshold` 0.45 (0…1, 0.05), `zcrThreshold` 0.25 (0…0.5, 0.01), `zcrLevelMarginDB` 6 (0…12, 0.5); `vadSpeechConfidenceThreshold` 0.5 (0…1, 0.05).

**VoiceBoostTuning** — `useVoiceBoostN` Bool true (effective = this AND `FeatureFlag.voiceBoostN`; keep `Settings.isVoiceBoostNEnabled` as a facade over this field); `targetLUFS` −17 (−30…−10, 0.5); `maxGainDB` 24 (0…36, 1); `minGainDB` −12 (−24…0, 1); `gainSmoothingTauSeconds` 0.5 (0.05…2.0, 0.05; ≈ current 0.95/0.05 @1152/44.1k); `adaptiveGainSmoothing` Bool false; `hpEnabled` true, `hpFrequency` 80 (40…300, 5), `hpQ` 0.707 (0.3…2.0, 0.01); `compEnabled` true, `compThresholdDB` −8 (−40…0, 0.5), `compRatio` 2 (1…20, 0.1), `compAttackMs` 100 (1…500, 1), `compReleaseMs` 400 (10…2000, 10), `compKneeWidthDB` 0 (0…24, 0.5; 0 = hard knee = current); `limiterCeilingDB` −2 (−6…−0.1, 0.1), `limiterLookaheadMs` 5 (1…20, 0.5), `limiterReleaseMs` 100 (10…1000, 10); `truePeakEnabled` Bool false.

**TimeStretchTuning** — `effectsPlayerAlgorithm` String enum .iPodTimeOther (default) / .spectral; `defaultPlayerAlgorithm` String enum .timeDomain (default) / .spectral / .varispeed.

- Forward-compat decode: hand-written `init(from:)` per struct using `decodeIfPresent ?? Self().field`.
- `TrimSilenceParameters` + `static preset(for: TrimSilenceAmount)` table (low −45.2 dB/522 ms/366 ms, medium −45.8/418/313, high −46.0/104/0; hysteresis/hold/crossfade 0, guard 5 s, .rms) and `AudioTuning.trimParameters(for:sampleRate:)` → preset unless `useCustomGate`.
- `AudioTuning.vbnConfig() -> VBNConfig` mapping.

**`podcasts/Constants.swift`**: `Notifications.audioTuningDidChange`, `UserDefaults.audioTuning = "SJAudioTuning"`.

**`podcasts/Settings.swift`**: `static var audioTuning: AudioTuning` — JSON blob in UserDefaults; setter early-returns on equality, removes key when `.default`, posts `audioTuningDidChange` via `NotificationCenter.postOnMainThread` (mirror `isLockScreenScrubbingDisabled` pattern). Corrupt blob → `.default`.

**`podcasts/PlaybackManager.swift`**:
- `EngineStateMirror`: add lock-guarded `var tuning: AudioTuning` and `var voiceBoostMeters: VoiceBoostMeters?` (`nonisolated struct VoiceBoostMeters { gainDB, measuredLUFS, limiterReductionDB: Float }`).
- `init`: seed `Self.engineState.tuning = Settings.audioTuning`; observe `audioTuningDidChange` → `handleAudioTuningChanged()`: update mirror; if `timeStretch` changed and playing on EffectsPlayer → reload current episode (existing `load(episode:autoPlay:overrideUpNext:)` path); else `player?.effectsDidChange()`.

## Phase 2 — VoiceBoostN C improvements

**`podcasts/VoiceBoostN.h` / `.c` / `_Internal.h`**:
- `VBNConfig` struct (fields mirroring VoiceBoostTuning incl. `initialGainDB` NAN-sentinel) + `VBN_GetDefaultConfig`, `VBN_CreateWithConfig`, `VBN_SetConfig`, `VBN_SetInitialGainDB`.
- Thread-safe config handoff: double-buffered `VBNConfig configSlots[2]` + `_Atomic int publishedSlot` + `_Atomic uint32_t configEpoch`; writer fills inactive slot then release-stores; `VBN_Process` checks epoch at top, memcpys and runs `applyConfig` (rebuild biquad setup, comp coeffs/LUT, limiter lookahead — clamp < deque capacity — clear deque, clamp targetGain).
- **Per-sample gain ramping**: replace constant `vDSP_vsmul` with `vDSP_vgen(lastAppliedGain → currentGain)` ramp × signal per channel. Smoothing frame-normalized: `alpha = expf(-frameCount / (tau·sampleRate))`; `adaptiveGainSmoothing` maps the existing dead `VBN_GAIN_SMOOTH_*` constants to per-band tau by gain-error (thresholds 10/5/2 dB).
- **Soft knee**: standard quadratic knee in dB domain, `gr = (1/R−1)(over+W/2)²/(2W)` inside |2·over| ≤ W; W=0 ⇒ exact current hard knee. LUT + interpolation to avoid per-sample log/pow; rebuilt in applyConfig.
- **True-peak** (when enabled): 4× oversampled magnitudes via ITU-R BS.1770-4 Annex 2 polyphase FIR (4 phases × 12 taps, standard coefficient table), per-channel 12-sample history, reset on VBN_Reset/config apply. Document CPU cost in header.
- **Multichannel BS.1770**: per-channel K-weighting delays (2 ch); circular buffer stores summed per-channel K-weighted squared energy; `measureBlock` uses `vDSP_sve/blockSize`. Note in PR: stereo dual-mono now reads ~+3 LU vs old ch0-only (spec-correct).
- Fix stale comments (−0.13 dBTP → actual; "true-peak" wording; adaptive-smoothing-clicks comment superseded).

**Call sites**: `AudioReadTask` → `VBN_CreateWithConfig(sampleRate, &tuning.vbnConfig())` + `setVBNConfig(_:)` under existing `objc_sync` lock; after `VBN_Process` write the three getters into `PlaybackManager.engineState.voiceBoostMeters` (nil on destroy). `DefaultPlayer`: cache `voiceBoostNActive` (tuning flag AND FeatureFlag) + `VBNConfig` copy behind `OSAllocatedUnfairLock` written in `effectsDidChange`; tapProcess uses cached values — removes the per-callback UserDefaults read at DefaultPlayer.swift:530; write meters from tap too.

## Phase 3 — Precomputed per-episode loudness

- **Migration 77** in DatabaseHelper.swift: `ALTER TABLE SJEpisode ADD COLUMN cachedLoudness REAL NOT NULL DEFAULT 0;` + same for SJUserEpisode; add column to BOTH baked CREATE TABLE blocks. 0 = unknown sentinel (real LUFS are negative).
- Follow cachedFrameCount blueprint end-to-end: `BaseEpisode.cachedLoudness`, Episode/UserEpisode model fields, `*+fromDatabase`, manager column arrays, `saveLoudness/findLoudness` on EpisodeDataManager + UserEpisodeDataManager + DataManager + EpisodeRepository.
- **New `podcasts/VoiceBoostNMeter.c`** (+ decls in VoiceBoostN.h, add to app target pbxproj): incremental `VBNLoudnessMeter` — shared K-weighting coeffs refactored into `VBN_ComputeKWeightingCoeffs`, 400 ms blocks / 100 ms hop, growable per-block energy array, two-pass gated `VBN_MeterIntegratedLUFS`.
- **New `podcasts/AdvancedAudio/EpisodeLoudnessScanner.swift`**: singleton, serial `.utility` queue, in-flight uuid dedupe; skip unless downloaded && loudness==0; AVAudioFile read in 32768-frame chunks → meter → `saveLoudness` (+ opportunistic `saveFrameCount`). Triggers: (1) `Constants.Notifications.episodeDownloaded` observer (gated on `FeatureFlag.voiceBoostN.enabled`), (2) `EffectsPlayer.play()` when loudness unknown.
- **Seeding**: EffectsPlayer passes `knownLUFS` into AudioReadTask → `VBN_SetInitialGainDB(state, targetLUFS − knownLUFS)` after create. DefaultPlayer reads loudness in `loadEpisode()` into a plain var, tap seeds after create. Unknown → adaptive path unchanged.

## Phase 4 — Trim-silence overhaul

**New `podcasts/AdvancedAudio/TrimSilenceDetector.swift`** (pure, `nonisolated`, unit-testable):
- API: `configure(parameters:sampleRate:framesPerBuffer:)`, `reset()`, `analyze(_ features: TrimFeatureFrame, stashedCount:, timeLeft:) -> Decision` where Decision = `.passthrough / .stash / .endGapEmitAll / .endGapTrim(keepBuffers:)`; `currentFloorDB` for the UI meter.
- ms→buffers: `max(1, Int((ms/1000 · sampleRate / framesPerBuffer).rounded()))`.
- Adaptive floor: 96-bin 1 dB histogram over ring of last `adaptiveWindowSeconds` of per-buffer rmsDB; floor = 10th percentile; gate = `max(floor + adaptiveOffsetDB, −70)`; fixed `thresholdDB` fallback until ≥2 s of data.
- State machine: open/closed with `exitDB = enterDB + hysteresisDB`, hold buffers refractory, existing 1000-cap → `maxGapHoldSeconds`, end-guard forces passthrough. Legacy-exact when hysteresis=hold=0, .rms.
- Discriminators: `.rms` level = rmsDB; `.heuristic` silent only if rmsDB < enter AND flatness > flatnessThreshold AND NOT(zcr > zcrThreshold && rmsDB > enter − zcrLevelMarginDB); `.vad` = heuristic + retrospective veto (below).

**`podcasts/AudioUtils.swift`**: `calculateZeroCrossingRate` (vDSP sign-product count), `calculateSpectralFlatness` (1024-pt vDSP_DFT + Hann, geometric/arithmetic mean ratio), `FFTSetupBox` class owning setup/scratch (created once per AudioReadTask); `crossfadeSplice(outgoing:incoming:overlapFrames:)` equal-power (precomputed cos/sin ramps, vDSP_vmul×2 + vDSP_vadd) and `trimLeadingFrames`.

**Crossfade splice** (only when crossfadeMs > 0; else legacy fades): at `.endGapTrim`, overlap M = crossfadeFrames ≤ 1152 between last kept buffer and resume buffer; trim M leading frames off resume; add M/sampleRate to saved-time stats. Edge case keepBuffers==0: keep 1 stashed buffer truncated to M frames as overlap carrier. Clamp M to resume length.

**New `podcasts/AdvancedAudio/TrimVoiceActivityAnalyzer.swift`**: wraps `SNAudioStreamAnalyzer` + `SNClassifySoundRequest(classifierIdentifier: .version1)` (0.5 s windows, 50% overlap) on a dedicated serial queue (copy channel 0 to scratch before dispatch — VBN mutates buffers in place; feed pre-DSP audio before VBN_Process). Results ring (64 entries, `OSAllocatedUnfairLock`): `(frameRange, speechConfidence)`. Read loop is non-blocking; at `.endGapTrim` time, if any result overlapping the to-be-dropped range has confidence > threshold → convert to `.endGapEmitAll` (retrospective veto). Stale (>2 s) or unavailable → degrade to heuristic. Recreate analyzer on seek (no rewind); `throws` construction falls back gracefully with FileLog.

**`podcasts/AudioReadTask.swift`**: delete old constants/per-amount functions/foundGap logic; own detector + params + optional VAD + FFTSetupBox; init takes `tuning: AudioTuning` (+ `knownLUFS`); replace `setTrimSilence` with `setTrimConfiguration(amount:tuning:)` (same locking; reset+flush stash on reconfig); trim branch computes `TrimFeatureFrame` (ZCR/flatness only when needed) → `detector.analyze` → switch on Decision reusing `buffersSavedDuringGap` and stats accounting; `performSeek` resets detector + VAD; `shutdown` tears down VAD.

**`podcasts/EffectsPlayer.swift`**: `effectsDidChange` reads mirror tuning → `setTrimConfiguration` + `setVBNConfig`; `play()` snapshots tuning, passes to AudioReadTask.

## Phase 5 — Unification, time-stretch, cleanups

- **DefaultPlayer legacy chain parity**: insert DynamicsProcessor AU into tap render chain (HP → dynamics → peak limiter; clone `createPeakLimiter` wiring; EffectsPlayer's exact params: Threshold −41, HeadRoom 40, Expansion 1/−100, Attack 0.05, Release 0.2, OverallGain 0); raise PreGain 8 → 11. Create/uninitialize in tapPrepare/tapUnprepare. Do NOT delete legacy chains (flag still defaults off in production) — note follow-up in comments.
- **Time-stretch**: EffectsPlayer `createTimePitchUnit()` switches on `tuning.timeStretch.effectsPlayerAlgorithm` (.iPodTimeOther = current custom AU; .spectral = plain `AVAudioUnitTimePitch()`); applied on engine build, live change handled by PlaybackManager reload (Phase 1). DefaultPlayer `performSetPlaybackRate`: `audioTimePitchAlgorithm` from tuning (.timeDomain/.spectral/.varispeed — live-settable) and replace `<0.5 → 1.0` snap with `max(0.5, rate)`; fix the sibling snap in `PlaybackEffects.globalEffects()` (~line 87) too.
- **Cleanups**: delete `EffectsPlayer.targetVolumeDbGain` (line 10); `DataManager.clearCachedAudioMetadata(episode:)` zeroing frameCount+loudness, called at download completion (`DownloadManager+URLSessionDelegate.processEpisode` ~line 170, `moveBufferedEpisodeCacheToEpisodeFile` ~DownloadManager.swift:339) and extended into existing zero-out sites (bulkUserFileDelete, AppDelegate restore ~line 314); keep mono→stereo iOS 16 workaround.

## Phase 6 — Advanced Audio settings screen

- **Step 0**: register `podcasts/AdvancedAudio/` as PBXFileSystemSynchronizedRootGroup in project.pbxproj (copy `Syncing` entry; add to target's fileSystemSynchronizedGroups + main group children).
- **L10n**: ~66 keys, `advanced_audio_*` prefix (+ `settings_advanced_audio` row title), translator comments, in `podcasts/en.lproj/Localizable.strings`; regenerate via `mise run generate:code`, commit `Strings+Generated.swift`.
- **`AdvancedAudioSettingsViewModel.swift`** (`@MainActor`, ObservableObject): `@Published var tuning` seeded from Settings; Combine pipeline `dropFirst → removeDuplicates → debounce(0.15 s, injectable) → Settings.audioTuning = $0` (live apply, coalesces slider drags and time-stretch reloads); 2 Hz meter polling Timer reading `PlaybackManager.engineState.voiceBoostMeters` (start/stop with appear/disappear); `resetTrim/Boost/Stretch/All`, `loadTrimPreset(_:)` (seeds custom fields from preset table, sets useCustomGate).
- **`TuningRows.swift`**: `TuningSliderRow` (title + monospacedDigit value+unit label + `Slider` with `.tint(AppTheme.color(for: .primaryInteractive01, theme: theme))`), `TuningStepperRow`, `TuningPickerRow` (`.pickerStyle(.menu)`), `TuningToggleRow`, `TuningResetButton` — all themed via `@EnvironmentObject theme` per FileSync conventions.
- **`AdvancedAudioSettingsView.swift`**: modeled on `FileSyncSettingsView` — `List { LiveStatus / TrimSilence / VoiceBoost(Normalization + Compressor&Limiter sections) / TimeStretch / GlobalReset }`, `.insetGrouped`, `.scrollContentBackground(.hidden)`, `primaryUi04` background. Trim section: custom-gate toggle gates sliders, Load-from-preset menu, footer explaining preset override; time-stretch footer warns about playback restart; global reset with confirmation alert.
- **`podcasts/SettingsViewController.swift`**: add `case advancedAudio` to TableRow, display `(L10n.settingsAdvancedAudio, UIImage(systemName: "slider.horizontal.3"))`, insert into the playback-adjacent section, push `PCHostingController(rootView: AdvancedAudioSettingsView().environmentObject(Theme.sharedTheme))` (copy `.fileSync` case at ~205).
- Existing `EffectsViewController` / `PodcastEffectsViewController` untouched — presets keep working; custom gate overrides their numbers only.

## Phase 7 — Tests

- **Test bridging header**: new `PocketCastsTests/PocketCastsTests-Bridging-Header.h` with `#include "VoiceBoostN.h"`; set `SWIFT_OBJC_BRIDGING_HEADER` + `HEADER_SEARCH_PATHS = $(SRCROOT)/podcasts` on the PocketCastsTests target (symbols resolve via BUNDLE_LOADER; do not compile the .c twice). Smoke-test `VBN_GetDefaultConfig().targetLUFS == -17` first; fallback = compile the C files into the test target.
- `AudioTuningTests`: defaults == legacy constants table, Codable round-trip, forward-compat decode (`{}`, unknown keys), preset table, effectiveGate/custom precedence, vbnConfig mapping.
- `SettingsAudioTuningTests`: get/set round-trip, default-removes-key, single notification, no-op write posts nothing, corrupt blob → default (clean key in setUp/tearDown).
- `TrimSilenceDetectorTests`: legacy-equivalence vs old buffer math @44.1k/1152; hysteresis; hold; adaptive floor converges on synthetic −60 dB floor (fallback first 2 s); ms→buffer at 22.05/44.1/48 k; end-guard; stash cap.
- `AudioFeatureExtractorTests`: sine (flatness < 0.1, ZCR ≈ 2f/sr), white noise (flatness > 0.6), silence guard; crossfadeSplice no-dip on DC buffers + frameLength shrink; trimLeadingFrames.
- `VoiceBoostNTests` (C via bridging header): meter ±0.5 LU on 997 Hz sine @−20 dBFS; stereo dual-mono +3.01 LU; gain-ramp continuity (no sample step > click threshold on config change); soft-knee static curve (W=6 at T−W/2 / T / T+W); limiter ceiling (sample-peak) + inter-sample-peak fixture caught only in true-peak mode; cross-thread VBN_SetConfig while processing; SetInitialGainDB seeds immediately.
- `AdvancedAudioSettingsViewModelTests` (`@MainActor`, debounce 0): commit, section resets, resetAll removes key, loadTrimPreset.
- Migration: extend `DatabaseHelperMigrationTests` + v73 fixture test (`ProductionDatabaseMigrationFixtureTests`) for cachedLoudness round-trip; `ONLY_TESTING=PocketCastsDataModelTests mise run test:staging`.

## Execution order

1. Phase 1 (foundation; no behavior change) + AudioTuning/Settings tests
2. Phase 2 (VBN C) + bridging header + VoiceBoostNTests
3. Phase 3 (meter, migration 77, scanner, seeding)
4. Phase 4 (detector + extractors + tests first, then AudioReadTask refactor, VAD last)
5. Phase 5 (unification, time-stretch, cleanups)
6. Phase 6 (L10n → generate:code → rows → VM → view → entry row) + VM tests
7. `mise run format`, `mise run check:static`

## Verification

- `mise run format` && `mise run check:static`
- `mise run test:staging` (app tests incl. new DSP/tuning tests); `ONLY_TESTING=PocketCastsDataModelTests mise run test:staging` (migration)
- `mise run build:staging`; install on booted simulator (explicit UDID per CLAUDE.md), then manually:
  - Settings → Advanced Audio renders, sliders themed, values persist across relaunch
  - Play a downloaded episode with trim silence on → live-drag trim threshold/crossfade and VBN target LUFS; audio changes within ~1 s, no clicks; meters section updates while playing
  - Toggle discriminator to VAD → playback continues (check FileLog for VAD fallback messages)
  - Change EffectsPlayer time-stretch algorithm mid-play → player reloads and resumes
  - Set speed 0.5× on a streamed episode → actually plays at 0.5 (snap removed)
  - Download an episode → verify cachedLoudness populated (scanner log), replay → instant gain (no ramp-up)
- Risks to watch: migration 77 baked-schema convergence (fixture test), stereo LUFS +3 LU shift (intentional, note in PR), audio-thread allocation confined to config-epoch changes, all new audio-path types explicitly `nonisolated`.
