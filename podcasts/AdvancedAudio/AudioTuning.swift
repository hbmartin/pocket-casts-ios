import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Decodes a `RawRepresentable` enum resiliently: a missing key OR an unrecognized raw
/// value (e.g. a case added by a newer build, seen after a downgrade) both fall back to
/// `default` instead of throwing — which would otherwise discard the entire surrounding
/// tuning blob via the `try?` in `Settings.audioTuning`.
private extension KeyedDecodingContainer {
    nonisolated func decodeEnum<T: RawRepresentable>(_ type: T.Type, forKey key: Key, default fallback: T) -> T where T.RawValue: Decodable {
        guard let raw = (try? decodeIfPresent(T.RawValue.self, forKey: key))else { return fallback }
        return T(rawValue: raw) ?? fallback
    }
}

/// Which signal features the trim-silence gate uses to decide speech vs silence.
nonisolated enum TrimDiscriminator: String, Codable, Equatable, Sendable, CaseIterable {
    /// Broadband RMS against the gate threshold (legacy behavior).
    case rms
    /// RMS plus zero-crossing-rate and spectral-flatness guards that protect
    /// quiet music/reverb tails and trailing fricatives.
    case heuristic
    /// Heuristic gating plus a retrospective SoundAnalysis speech-confidence
    /// veto before any silence is dropped. Falls back to `.heuristic` when the
    /// system analyzer is unavailable or its results are stale.
    case vad
}

/// User-tunable parameters for the trim-silence gate. Defaults reproduce the
/// legacy medium preset; the preset table below stays authoritative until
/// `useCustomGate` is switched on.
nonisolated struct TrimTuning: Codable, Equatable, Sendable {
    /// When false the Low/Medium/High presets picked in the effects panel win;
    /// when true the fields below replace the preset's numbers.
    var useCustomGate = false
    var discriminator: TrimDiscriminator = .rms

    /// Fixed gate threshold (dBFS of buffer RMS) used when the adaptive floor
    /// is off or hasn't gathered enough history yet.
    var thresholdDB: Double = -45.83
    var adaptiveNoiseFloor = false
    /// Gate sits this many dB above the estimated noise floor.
    var adaptiveOffsetDB: Double = 12
    /// How much recent audio the noise-floor histogram remembers.
    var adaptiveWindowSeconds: Double = 10

    /// The gate reopens only when the level exceeds threshold + hysteresis.
    var hysteresisDB: Double = 0
    /// After the gate reopens, it cannot close again for this long.
    var holdTimeMs: Double = 0

    /// Gaps shorter than this are never trimmed.
    var minGapMs: Double = 418
    /// How much of each trimmed gap is kept (re-inserted) at the splice.
    var keepGapMs: Double = 313
    /// Equal-power overlap at each splice point; 0 keeps the legacy
    /// fade-out-then-fade-in splice.
    var crossfadeMs: Double = 0
    /// Silence is never trimmed from the last part of an episode.
    var endGuardSeconds: Double = 5
    /// Safety cap on how much silence is held in memory during one gap.
    var maxGapHoldSeconds: Double = 26

    // Heuristic discriminator guards
    /// Buffers only count as silent when spectral flatness exceeds this
    /// (noise-like); tonal content such as music tails is protected.
    var flatnessThreshold: Double = 0.45
    /// Quiet-but-high-ZCR buffers (trailing fricatives) are protected.
    var zcrThreshold: Double = 0.25
    /// The ZCR guard applies within this many dB below the gate threshold.
    var zcrLevelMarginDB: Double = 6

    /// VAD veto: gaps overlapping speech results above this confidence are not trimmed.
    var vadSpeechConfidenceThreshold: Double = 0.5

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        useCustomGate = try container.decodeIfPresent(Bool.self, forKey: .useCustomGate) ?? defaults.useCustomGate
        discriminator = container.decodeEnum(TrimDiscriminator.self, forKey: .discriminator, default: defaults.discriminator)
        thresholdDB = try container.decodeIfPresent(Double.self, forKey: .thresholdDB) ?? defaults.thresholdDB
        adaptiveNoiseFloor = try container.decodeIfPresent(Bool.self, forKey: .adaptiveNoiseFloor) ?? defaults.adaptiveNoiseFloor
        adaptiveOffsetDB = try container.decodeIfPresent(Double.self, forKey: .adaptiveOffsetDB) ?? defaults.adaptiveOffsetDB
        adaptiveWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .adaptiveWindowSeconds) ?? defaults.adaptiveWindowSeconds
        hysteresisDB = try container.decodeIfPresent(Double.self, forKey: .hysteresisDB) ?? defaults.hysteresisDB
        holdTimeMs = try container.decodeIfPresent(Double.self, forKey: .holdTimeMs) ?? defaults.holdTimeMs
        minGapMs = try container.decodeIfPresent(Double.self, forKey: .minGapMs) ?? defaults.minGapMs
        keepGapMs = try container.decodeIfPresent(Double.self, forKey: .keepGapMs) ?? defaults.keepGapMs
        crossfadeMs = try container.decodeIfPresent(Double.self, forKey: .crossfadeMs) ?? defaults.crossfadeMs
        endGuardSeconds = try container.decodeIfPresent(Double.self, forKey: .endGuardSeconds) ?? defaults.endGuardSeconds
        maxGapHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .maxGapHoldSeconds) ?? defaults.maxGapHoldSeconds
        flatnessThreshold = try container.decodeIfPresent(Double.self, forKey: .flatnessThreshold) ?? defaults.flatnessThreshold
        zcrThreshold = try container.decodeIfPresent(Double.self, forKey: .zcrThreshold) ?? defaults.zcrThreshold
        zcrLevelMarginDB = try container.decodeIfPresent(Double.self, forKey: .zcrLevelMarginDB) ?? defaults.zcrLevelMarginDB
        vadSpeechConfidenceThreshold = try container.decodeIfPresent(Double.self, forKey: .vadSpeechConfidenceThreshold) ?? defaults.vadSpeechConfidenceThreshold
    }

    // Valid ranges — the single source of truth shared by the settings-screen sliders
    // and `clamped()`. Every default above sits inside its range.
    static let thresholdDBRange: ClosedRange<Double> = -70 ... -20
    static let adaptiveOffsetDBRange: ClosedRange<Double> = 3 ... 24
    static let adaptiveWindowSecondsRange: ClosedRange<Double> = 5 ... 30
    static let hysteresisDBRange: ClosedRange<Double> = 0 ... 12
    static let holdTimeMsRange: ClosedRange<Double> = 0 ... 500
    static let minGapMsRange: ClosedRange<Double> = 0 ... 1500
    static let keepGapMsRange: ClosedRange<Double> = 0 ... 1000
    static let crossfadeMsRange: ClosedRange<Double> = 0 ... 200
    static let endGuardSecondsRange: ClosedRange<Double> = 0 ... 30
    static let maxGapHoldSecondsRange: ClosedRange<Double> = 1 ... 120
    static let flatnessThresholdRange: ClosedRange<Double> = 0 ... 1
    static let zcrThresholdRange: ClosedRange<Double> = 0 ... 0.5
    static let zcrLevelMarginDBRange: ClosedRange<Double> = 0 ... 12
    static let vadSpeechConfidenceThresholdRange: ClosedRange<Double> = 0 ... 1

    /// Clamps every stored value to its valid range so a corrupt or hand-edited persisted
    /// blob can't feed out-of-range numbers to the DSP. Sliders clamp the thumb, not the
    /// stored/decoded value.
    func clamped() -> TrimTuning {
        var c = self
        c.thresholdDB = thresholdDB.clamped(to: Self.thresholdDBRange)
        c.adaptiveOffsetDB = adaptiveOffsetDB.clamped(to: Self.adaptiveOffsetDBRange)
        c.adaptiveWindowSeconds = adaptiveWindowSeconds.clamped(to: Self.adaptiveWindowSecondsRange)
        c.hysteresisDB = hysteresisDB.clamped(to: Self.hysteresisDBRange)
        c.holdTimeMs = holdTimeMs.clamped(to: Self.holdTimeMsRange)
        c.minGapMs = minGapMs.clamped(to: Self.minGapMsRange)
        c.keepGapMs = keepGapMs.clamped(to: Self.keepGapMsRange)
        c.crossfadeMs = crossfadeMs.clamped(to: Self.crossfadeMsRange)
        c.endGuardSeconds = endGuardSeconds.clamped(to: Self.endGuardSecondsRange)
        c.maxGapHoldSeconds = maxGapHoldSeconds.clamped(to: Self.maxGapHoldSecondsRange)
        c.flatnessThreshold = flatnessThreshold.clamped(to: Self.flatnessThresholdRange)
        c.zcrThreshold = zcrThreshold.clamped(to: Self.zcrThresholdRange)
        c.zcrLevelMarginDB = zcrLevelMarginDB.clamped(to: Self.zcrLevelMarginDBRange)
        c.vadSpeechConfidenceThreshold = vadSpeechConfidenceThreshold.clamped(to: Self.vadSpeechConfidenceThresholdRange)
        return c
    }
}

/// User-tunable parameters for the VoiceBoostN normalization chain. Defaults
/// mirror the constants in VoiceBoostN_Internal.h so default tuning behaves
/// exactly like the shipped DSP.
nonisolated struct VoiceBoostTuning: Codable, Equatable, Sendable {
    /// When false the legacy AudioUnit chain handles volume boost.
    var useVoiceBoostN = true

    var targetLUFS: Double = -17
    var maxGainDB: Double = 24
    var minGainDB: Double = -12
    /// One-pole time constant for gain convergence; 0.5 s matches the legacy
    /// fixed 0.95/0.05 smoothing at 1152 frames / 44.1 kHz.
    var gainSmoothingTauSeconds: Double = 0.5
    /// Converge faster while far from target (per-sample ramping keeps it click-free).
    var adaptiveGainSmoothing = false

    var hpEnabled = true
    var hpFrequency: Double = 80
    var hpQ: Double = 0.707

    var compEnabled = true
    var compThresholdDB: Double = -8
    var compRatio: Double = 2
    var compAttackMs: Double = 100
    var compReleaseMs: Double = 400
    /// 0 = hard knee (legacy behavior).
    var compKneeWidthDB: Double = 0

    var limiterCeilingDB: Double = -2
    var limiterLookaheadMs: Double = 5
    var limiterReleaseMs: Double = 100
    /// 4x oversampled inter-sample peak detection (ITU-R BS.1770-4 Annex 2).
    var truePeakEnabled = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        useVoiceBoostN = try container.decodeIfPresent(Bool.self, forKey: .useVoiceBoostN) ?? defaults.useVoiceBoostN
        targetLUFS = try container.decodeIfPresent(Double.self, forKey: .targetLUFS) ?? defaults.targetLUFS
        maxGainDB = try container.decodeIfPresent(Double.self, forKey: .maxGainDB) ?? defaults.maxGainDB
        minGainDB = try container.decodeIfPresent(Double.self, forKey: .minGainDB) ?? defaults.minGainDB
        gainSmoothingTauSeconds = try container.decodeIfPresent(Double.self, forKey: .gainSmoothingTauSeconds) ?? defaults.gainSmoothingTauSeconds
        adaptiveGainSmoothing = try container.decodeIfPresent(Bool.self, forKey: .adaptiveGainSmoothing) ?? defaults.adaptiveGainSmoothing
        hpEnabled = try container.decodeIfPresent(Bool.self, forKey: .hpEnabled) ?? defaults.hpEnabled
        hpFrequency = try container.decodeIfPresent(Double.self, forKey: .hpFrequency) ?? defaults.hpFrequency
        hpQ = try container.decodeIfPresent(Double.self, forKey: .hpQ) ?? defaults.hpQ
        compEnabled = try container.decodeIfPresent(Bool.self, forKey: .compEnabled) ?? defaults.compEnabled
        compThresholdDB = try container.decodeIfPresent(Double.self, forKey: .compThresholdDB) ?? defaults.compThresholdDB
        compRatio = try container.decodeIfPresent(Double.self, forKey: .compRatio) ?? defaults.compRatio
        compAttackMs = try container.decodeIfPresent(Double.self, forKey: .compAttackMs) ?? defaults.compAttackMs
        compReleaseMs = try container.decodeIfPresent(Double.self, forKey: .compReleaseMs) ?? defaults.compReleaseMs
        compKneeWidthDB = try container.decodeIfPresent(Double.self, forKey: .compKneeWidthDB) ?? defaults.compKneeWidthDB
        limiterCeilingDB = try container.decodeIfPresent(Double.self, forKey: .limiterCeilingDB) ?? defaults.limiterCeilingDB
        limiterLookaheadMs = try container.decodeIfPresent(Double.self, forKey: .limiterLookaheadMs) ?? defaults.limiterLookaheadMs
        limiterReleaseMs = try container.decodeIfPresent(Double.self, forKey: .limiterReleaseMs) ?? defaults.limiterReleaseMs
        truePeakEnabled = try container.decodeIfPresent(Bool.self, forKey: .truePeakEnabled) ?? defaults.truePeakEnabled
    }

    // Valid ranges — shared by the settings-screen sliders and `clamped()`.
    static let targetLUFSRange: ClosedRange<Double> = -30 ... -10
    static let maxGainDBRange: ClosedRange<Double> = 0 ... 36
    static let minGainDBRange: ClosedRange<Double> = -24 ... 0
    static let gainSmoothingTauSecondsRange: ClosedRange<Double> = 0.05 ... 2
    static let hpFrequencyRange: ClosedRange<Double> = 40 ... 300
    static let hpQRange: ClosedRange<Double> = 0.3 ... 2
    static let compThresholdDBRange: ClosedRange<Double> = -40 ... 0
    static let compRatioRange: ClosedRange<Double> = 1 ... 20
    static let compAttackMsRange: ClosedRange<Double> = 1 ... 500
    static let compReleaseMsRange: ClosedRange<Double> = 10 ... 2000
    static let compKneeWidthDBRange: ClosedRange<Double> = 0 ... 24
    static let limiterCeilingDBRange: ClosedRange<Double> = -6 ... -0.1
    static let limiterLookaheadMsRange: ClosedRange<Double> = 1 ... 20
    static let limiterReleaseMsRange: ClosedRange<Double> = 10 ... 1000

    /// Clamps every stored value to its valid range (see `TrimTuning.clamped()`).
    func clamped() -> VoiceBoostTuning {
        var c = self
        c.targetLUFS = targetLUFS.clamped(to: Self.targetLUFSRange)
        c.maxGainDB = maxGainDB.clamped(to: Self.maxGainDBRange)
        c.minGainDB = minGainDB.clamped(to: Self.minGainDBRange)
        c.gainSmoothingTauSeconds = gainSmoothingTauSeconds.clamped(to: Self.gainSmoothingTauSecondsRange)
        c.hpFrequency = hpFrequency.clamped(to: Self.hpFrequencyRange)
        c.hpQ = hpQ.clamped(to: Self.hpQRange)
        c.compThresholdDB = compThresholdDB.clamped(to: Self.compThresholdDBRange)
        c.compRatio = compRatio.clamped(to: Self.compRatioRange)
        c.compAttackMs = compAttackMs.clamped(to: Self.compAttackMsRange)
        c.compReleaseMs = compReleaseMs.clamped(to: Self.compReleaseMsRange)
        c.compKneeWidthDB = compKneeWidthDB.clamped(to: Self.compKneeWidthDBRange)
        c.limiterCeilingDB = limiterCeilingDB.clamped(to: Self.limiterCeilingDBRange)
        c.limiterLookaheadMs = limiterLookaheadMs.clamped(to: Self.limiterLookaheadMsRange)
        c.limiterReleaseMs = limiterReleaseMs.clamped(to: Self.limiterReleaseMsRange)
        return c
    }
}

/// Time-stretch algorithm choices per player backend.
nonisolated struct TimeStretchTuning: Codable, Equatable, Sendable {
    enum EffectsPlayerAlgorithm: String, Codable, Equatable, Sendable, CaseIterable {
        /// The iPod-era speech-tuned unit the app has always used.
        case iPodTimeOther
        /// Apple's newer spectral (phase-vocoder style) time pitch unit.
        case spectral
    }

    enum DefaultPlayerAlgorithm: String, Codable, Equatable, Sendable, CaseIterable {
        case timeDomain
        case spectral
        /// No time-domain correction; pitch shifts with rate.
        case varispeed

        var avAlgorithm: AVAudioTimePitchAlgorithm {
            switch self {
            case .timeDomain: return .timeDomain
            case .spectral: return .spectral
            case .varispeed: return .varispeed
            }
        }
    }

    var effectsPlayerAlgorithm: EffectsPlayerAlgorithm = .iPodTimeOther
    var defaultPlayerAlgorithm: DefaultPlayerAlgorithm = .timeDomain

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        effectsPlayerAlgorithm = container.decodeEnum(EffectsPlayerAlgorithm.self, forKey: .effectsPlayerAlgorithm, default: defaults.effectsPlayerAlgorithm)
        defaultPlayerAlgorithm = container.decodeEnum(DefaultPlayerAlgorithm.self, forKey: .defaultPlayerAlgorithm, default: defaults.defaultPlayerAlgorithm)
    }
}

/// The full advanced-audio tuning snapshot. Persisted as one JSON blob (see
/// `Settings.audioTuning`) so the audio engine always reads one consistent value
/// through `PlaybackManager.engineState`.
/// "Normalize volume": pure gain-to-target-LUFS playback (meter + gain +
/// true-peak safety limiter) with none of VoiceBoost's compression or filtering
/// character. When both VoiceBoost and Normalize are on, VoiceBoost wins — it
/// already normalizes loudness as part of its chain.
nonisolated struct NormalizeTuning: Codable, Equatable, Sendable {
    var enabled = false

    var targetLUFS: Double = -16

    static let targetLUFSRange: ClosedRange<Double> = -30 ... -8

    func clamped() -> NormalizeTuning {
        var clamped = self
        clamped.targetLUFS = min(max(targetLUFS, Self.targetLUFSRange.lowerBound), Self.targetLUFSRange.upperBound)
        return clamped
    }
}

nonisolated struct AudioTuning: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = AudioTuning.currentVersion
    var trim = TrimTuning()
    var voiceBoost = VoiceBoostTuning()
    var timeStretch = TimeStretchTuning()
    var normalize = NormalizeTuning()

    nonisolated static let `default` = AudioTuning()

    var isDefault: Bool { self == .default }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? AudioTuning.currentVersion
        version = decodedVersion
        trim = (try container.decodeIfPresent(TrimTuning.self, forKey: .trim) ?? TrimTuning()).clamped()
        voiceBoost = (try container.decodeIfPresent(VoiceBoostTuning.self, forKey: .voiceBoost) ?? VoiceBoostTuning()).clamped()
        timeStretch = try container.decodeIfPresent(TimeStretchTuning.self, forKey: .timeStretch) ?? TimeStretchTuning()
        normalize = (try container.decodeIfPresent(NormalizeTuning.self, forKey: .normalize) ?? NormalizeTuning()).clamped()
        migrate(fromVersion: decodedVersion)
        version = AudioTuning.currentVersion
    }

    /// Migration seam for future schema bumps. Field-level `decodeIfPresent` already
    /// tolerates added fields, so there are no migrations at v1; this is where a future
    /// `currentVersion` increment would transform older payloads before use.
    private mutating func migrate(fromVersion oldVersion: Int) {
        // No migrations yet (currentVersion == 1).
    }
}

// MARK: - Trim gate parameter resolution

/// The resolved parameter set the trim-silence detector runs with. Times are in
/// milliseconds/seconds; the detector converts to buffer counts for the file's
/// actual sample rate.
nonisolated struct TrimSilenceParameters: Equatable, Sendable {
    var enterThresholdDB: Double
    var hysteresisDB: Double
    var holdTimeMs: Double
    var minGapMs: Double
    var keepGapMs: Double
    var crossfadeMs: Double
    var endGuardSeconds: Double
    var maxGapHoldSeconds: Double
    var useAdaptiveFloor: Bool
    var adaptiveOffsetDB: Double
    var adaptiveWindowSeconds: Double
    var discriminator: TrimDiscriminator
    var flatnessThreshold: Double
    var zcrThreshold: Double
    var zcrLevelMarginDB: Double
    var vadSpeechConfidenceThreshold: Double

    /// The legacy preset table. Thresholds are the old linear RMS gates in dB
    /// (0.0055 / 0.00511 / 0.005); gap/keep are the old buffer counts expressed
    /// as milliseconds at 44.1 kHz with 1152-frame buffers (26.12 ms/buffer),
    /// so the detector's ms→buffer conversion lands on the identical counts.
    static func preset(for amount: TrimSilenceAmount) -> TrimSilenceParameters {
        let base = TrimSilenceParameters(
            enterThresholdDB: -45.83,
            hysteresisDB: 0,
            holdTimeMs: 0,
            minGapMs: 418,
            keepGapMs: 313,
            crossfadeMs: 0,
            endGuardSeconds: 5,
            maxGapHoldSeconds: 26,
            useAdaptiveFloor: false,
            adaptiveOffsetDB: 12,
            adaptiveWindowSeconds: 10,
            discriminator: .rms,
            flatnessThreshold: 0.45,
            zcrThreshold: 0.25,
            zcrLevelMarginDB: 6,
            vadSpeechConfidenceThreshold: 0.5
        )

        var params = base
        switch amount {
        case .off, .medium:
            break
        case .low:
            params.enterThresholdDB = -45.19 // 0.0055
            params.minGapMs = 522 // 20 buffers
            params.keepGapMs = 366 // 14 buffers
        case .high:
            params.enterThresholdDB = -46.02 // 0.005
            params.minGapMs = 104 // 4 buffers
            params.keepGapMs = 0
        }

        return params
    }
}

nonisolated extension AudioTuning {
    /// Resolves the gate parameters the detector should run with: the preset for
    /// `amount` unless the user has switched on custom tuning.
    func trimParameters(for amount: TrimSilenceAmount) -> TrimSilenceParameters {
        guard trim.useCustomGate else { return .preset(for: amount) }

        return TrimSilenceParameters(
            enterThresholdDB: trim.thresholdDB,
            hysteresisDB: trim.hysteresisDB,
            holdTimeMs: trim.holdTimeMs,
            minGapMs: trim.minGapMs,
            keepGapMs: trim.keepGapMs,
            crossfadeMs: trim.crossfadeMs,
            endGuardSeconds: trim.endGuardSeconds,
            maxGapHoldSeconds: trim.maxGapHoldSeconds,
            useAdaptiveFloor: trim.adaptiveNoiseFloor,
            adaptiveOffsetDB: trim.adaptiveOffsetDB,
            adaptiveWindowSeconds: trim.adaptiveWindowSeconds,
            discriminator: trim.discriminator,
            flatnessThreshold: trim.flatnessThreshold,
            zcrThreshold: trim.zcrThreshold,
            zcrLevelMarginDB: trim.zcrLevelMarginDB,
            vadSpeechConfidenceThreshold: trim.vadSpeechConfidenceThreshold
        )
    }
}
