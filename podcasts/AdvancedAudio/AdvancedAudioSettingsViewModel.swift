import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Backs the Advanced Audio screen: edits flow into `tuning`, get debounced
/// (so slider drags coalesce), then commit to `Settings.audioTuning`, whose
/// setter notifies PlaybackManager for live apply.
@MainActor
final class AdvancedAudioSettingsViewModel: ObservableObject {
    @Published var tuning: AudioTuning = Settings.audioTuning
    @Published private(set) var meters: PlaybackManager.EngineStateMirror.VoiceBoostMeters?
    @Published private(set) var isPlaying = false
    @Published var showingResetConfirmation = false

    private var cancellables = Set<AnyCancellable>()
    private var meterTimer: AnyCancellable?

    init(commitDebounce: TimeInterval = 0.15) {
        $tuning
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .seconds(commitDebounce), scheduler: DispatchQueue.main)
            .sink { Settings.audioTuning = $0 }
            .store(in: &cancellables)
    }

    var voiceBoostNFlagEnabled: Bool {
        FeatureFlag.voiceBoostN.enabled
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

    /// Seeds the custom trim fields from one of the Low/Medium/High presets and
    /// switches custom gating on, so users can tune from a known starting point.
    func loadTrimPreset(_ amount: TrimSilenceAmount) {
        let preset = TrimSilenceParameters.preset(for: amount)
        tuning.trim.useCustomGate = true
        tuning.trim.thresholdDB = preset.enterThresholdDB
        tuning.trim.hysteresisDB = preset.hysteresisDB
        tuning.trim.holdTimeMs = preset.holdTimeMs
        tuning.trim.minGapMs = preset.minGapMs
        tuning.trim.keepGapMs = preset.keepGapMs
        tuning.trim.crossfadeMs = preset.crossfadeMs
        tuning.trim.endGuardSeconds = preset.endGuardSeconds
        tuning.trim.maxGapHoldSeconds = preset.maxGapHoldSeconds
    }
}
