import Combine
import Foundation
import Observation
import PocketCastsDataModel
import PocketCastsUtils

/// Backs the Advanced Audio screen: edits flow into `tuning`, get debounced (so slider
/// drags coalesce), then commit to `Settings.audioTuning`, whose setter notifies
/// PlaybackManager for live apply.
///
/// `@Observable` (not `ObservableObject`) so a change to one property only invalidates the
/// views that actually read it — e.g. a slider drag no longer re-renders the live-meter
/// section, and 2 Hz meter updates no longer re-render the tuning sections.
@Observable
@MainActor
final class AdvancedAudioSettingsViewModel {
    var tuning: AudioTuning = Settings.audioTuning {
        // Any edit — from a slider binding, a reset, or a preset — schedules a debounced
        // commit. (Property observers don't fire for the initializer default, so loading
        // from Settings at init doesn't spuriously re-commit.)
        didSet { scheduleCommit() }
    }
    private(set) var meters: PlaybackManager.EngineStateMirror.VoiceBoostMeters?
    private(set) var isPlaying = false
    var showingResetConfirmation = false

    /// Adaptive effects switching (Item 14). Lives outside the tuning blob — a
    /// runtime override, not a tuning value — and applies immediately (its
    /// setter rides the tuning-change notification).
    var adaptiveEffects: Bool = Settings.adaptiveEffects() {
        didSet { Settings.setAdaptiveEffects(adaptiveEffects) }
    }

    @ObservationIgnored private let commitDebounce: TimeInterval
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var meterTimer: AnyCancellable?

    init(commitDebounce: TimeInterval = 0.15) {
        self.commitDebounce = commitDebounce
    }

    // MARK: - Commit

    /// Debounced commit of the current tuning to `Settings` (which notifies PlaybackManager
    /// for live apply). Invoked from `tuning.didSet`; each call reschedules with the latest
    /// value so a rapid drag coalesces into one write. A zero debounce commits synchronously
    /// (used by tests and safe for one-shot programmatic edits).
    func scheduleCommit() {
        commitTask?.cancel()
        commitTask = nil
        guard commitDebounce > 0 else {
            Settings.audioTuning = tuning
            return
        }
        let snapshot = tuning
        let debounce = commitDebounce
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(debounce))
            guard !Task.isCancelled else { return }
            Settings.audioTuning = snapshot
            self?.commitTask = nil
        }
    }

    /// Commits any pending change immediately. Call on screen dismissal so an edit made
    /// within the debounce window isn't lost when the pending Task is cancelled.
    func flush() {
        commitTask?.cancel()
        commitTask = nil
        Settings.audioTuning = tuning
    }

    // MARK: - Live meters

    func startMeterPolling() {
        refreshMeters()
        meterTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMeters()
            }
    }

    func stopMeterPolling() {
        meterTimer = nil
    }

    private func refreshMeters() {
        isPlaying = PlaybackManager.shared.playing()
        meters = PlaybackManager.engineState.voiceBoostMeters
    }

    // MARK: - Resets and presets

    func resetTrimSilence() {
        tuning.trim = TrimTuning()
    }

    func resetVoiceBoost() {
        tuning.voiceBoost = VoiceBoostTuning()
    }

    func resetTimeStretch() {
        tuning.timeStretch = TimeStretchTuning()
    }

    func resetAll() {
        tuning = .default
    }

    /// Seeds the custom trim fields from one of the Low/Medium/High presets and switches
    /// custom gating on, so users can tune from a known starting point.
    func loadTrimPreset(_ amount: TrimSilenceAmount) {
        let preset = TrimSilenceParameters.preset(for: amount)
        var trim = tuning.trim
        trim.useCustomGate = true
        trim.thresholdDB = preset.enterThresholdDB
        trim.hysteresisDB = preset.hysteresisDB
        trim.holdTimeMs = preset.holdTimeMs
        trim.minGapMs = preset.minGapMs
        trim.keepGapMs = preset.keepGapMs
        trim.crossfadeMs = preset.crossfadeMs
        trim.endGuardSeconds = preset.endGuardSeconds
        trim.maxGapHoldSeconds = preset.maxGapHoldSeconds
        tuning.trim = trim.clamped()
    }
}
