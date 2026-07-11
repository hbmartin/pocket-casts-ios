import Foundation

/// Per-buffer signal features the trim-silence gate decides on. Extracted by
/// AudioReadTask (RMS always; ZCR/flatness only for the heuristic and VAD
/// discriminators) so the detector itself stays pure and unit-testable.
nonisolated struct TrimFeatureFrame: Sendable {
    var rmsDB: Float
    var zeroCrossingRate: Float = 0
    var spectralFlatness: Float = 1
    /// Speech confidence from the system VAD covering this frame position;
    /// nil when no (fresh) result is available.
    var vadSpeechConfidence: Float?
}

/// The trim-silence gate: a state machine over per-buffer feature frames that
/// decides what AudioReadTask should do with each buffer. Pure logic — no
/// audio APIs — configured from `TrimSilenceParameters`.
///
/// With hysteresis and hold at 0, the adaptive floor off and the `.rms`
/// discriminator, this reproduces the legacy AudioReadTask behavior exactly.
///
/// Not thread-safe; AudioReadTask drives it under its own lock.
nonisolated final class TrimSilenceDetector {
    enum Decision: Equatable {
        /// Gate open: emit the buffer.
        case passthrough
        /// Inside a gap: hold the buffer on the gap stack.
        case stash
        /// Gap ended but was too short to trim: flush the stack, then emit the buffer.
        case endGapEmitAll
        /// Gap ended and is trimmable: keep the first `keepBuffers` stashed
        /// buffers, drop the rest, splice, then emit the buffer.
        case endGapTrim(keepBuffers: Int)
    }

    private(set) var parameters = TrimSilenceParameters.preset(for: .medium)
    private var sampleRate: Double = 44100
    private var framesPerBuffer = 1152

    // Derived buffer counts
    private(set) var minGapBuffers = 1
    private(set) var keepBuffers = 0
    private(set) var holdBuffers = 0
    private(set) var maxStashBuffers = 1000
    private(set) var crossfadeFrames = 0

    // Gate state
    private var inGap = false
    private var holdRemaining = 0

    // Adaptive noise floor: 1 dB histogram over the last N buffers of rmsDB
    private static let histogramMinDB: Float = -95
    private static let histogramBins = 96
    private var histogram = [Int](repeating: 0, count: TrimSilenceDetector.histogramBins)
    private var historyRing = [Int]()
    private var historyCapacity = 0
    private var historyCount = 0
    private var historyWriteIndex = 0
    /// Buffers of history required before the adaptive floor is trusted (~2 s).
    private var minHistoryBuffers = 1

    // MARK: - Configuration

    /// Applies new parameters. Gate state (in-gap, hold) is preserved so a
    /// live reconfiguration mid-gap never orphans stashed buffers; the
    /// noise-floor history restarts because its window size may have changed.
    func configure(parameters: TrimSilenceParameters, sampleRate: Double, framesPerBuffer: Int) {
        self.parameters = parameters
        self.sampleRate = max(sampleRate, 8000)
        self.framesPerBuffer = max(framesPerBuffer, 1)

        minGapBuffers = buffers(forMs: parameters.minGapMs)
        keepBuffers = parameters.keepGapMs <= 0 ? 0 : buffers(forMs: parameters.keepGapMs)
        holdBuffers = parameters.holdTimeMs <= 0 ? 0 : buffers(forMs: parameters.holdTimeMs)
        maxStashBuffers = max(minGapBuffers + 1, buffers(forMs: parameters.maxGapHoldSeconds * 1000))
        crossfadeFrames = parameters.crossfadeMs <= 0 ? 0 : min(self.framesPerBuffer, Int(parameters.crossfadeMs / 1000 * self.sampleRate))

        historyCapacity = max(4, buffers(forMs: parameters.adaptiveWindowSeconds * 1000))
        minHistoryBuffers = max(2, buffers(forMs: 2000))
        resetNoiseFloorHistory()
    }

    /// Clears all gate and noise-floor state. Call on seek, together with
    /// emptying the gap stack.
    func reset() {
        inGap = false
        holdRemaining = 0
        resetNoiseFloorHistory()
    }

    private func resetNoiseFloorHistory() {
        histogram = [Int](repeating: 0, count: Self.histogramBins)
        historyRing = [Int](repeating: 0, count: historyCapacity)
        historyCount = 0
        historyWriteIndex = 0
    }

    private func buffers(forMs ms: Double) -> Int {
        max(1, Int((ms / 1000 * sampleRate / Double(framesPerBuffer)).rounded()))
    }

    // MARK: - Adaptive noise floor

    /// The current noise-floor estimate (10th percentile of recent buffer RMS),
    /// or nil until enough history has accumulated. Also surfaced to the
    /// Advanced Audio screen for debugging.
    var currentFloorDB: Float? {
        guard historyCount >= minHistoryBuffers else { return nil }

        let target = max(1, historyCount / 10)
        var cumulative = 0
        for bin in 0 ..< Self.histogramBins {
            cumulative += histogram[bin]
            if cumulative >= target {
                return Self.histogramMinDB + Float(bin)
            }
        }
        return nil
    }

    private func recordLevel(_ rmsDB: Float) {
        guard historyCapacity > 0 else { return }

        let clamped = min(max(rmsDB, Self.histogramMinDB), Self.histogramMinDB + Float(Self.histogramBins - 1))
        let bin = Int(clamped - Self.histogramMinDB)

        if historyCount == historyCapacity {
            histogram[historyRing[historyWriteIndex]] -= 1
        } else {
            historyCount += 1
        }
        historyRing[historyWriteIndex] = bin
        histogram[bin] += 1
        historyWriteIndex = (historyWriteIndex + 1) % historyCapacity
    }

    /// The gate-enter threshold currently in effect: the adaptive floor plus
    /// offset when enabled and warmed up, else the fixed threshold.
    var effectiveEnterThresholdDB: Float {
        if parameters.useAdaptiveFloor, let floor = currentFloorDB {
            return max(floor + Float(parameters.adaptiveOffsetDB), -70)
        }
        return Float(parameters.enterThresholdDB)
    }

    // MARK: - Analysis

    func analyze(_ features: TrimFeatureFrame, stashedCount: Int, timeLeft: TimeInterval) -> Decision {
        recordLevel(features.rmsDB)

        let enterDB = effectiveEnterThresholdDB
        let exitDB = enterDB + Float(parameters.hysteresisDB)
        let levelDB = discriminatedLevel(features, enterDB: enterDB, exitDB: exitDB)

        // never trim near the end of the episode: force the gate open
        let endGuarded = timeLeft <= parameters.endGuardSeconds

        if !inGap {
            if !endGuarded, levelDB < enterDB, holdRemaining == 0 {
                inGap = true
                return .stash
            }
            if holdRemaining > 0 { holdRemaining -= 1 }
            return .passthrough
        }

        // inside a gap: close it when speech resumes, the end guard engages,
        // or the stash safety cap is hit
        if endGuarded || levelDB > exitDB || stashedCount >= maxStashBuffers {
            inGap = false
            holdRemaining = holdBuffers
            if stashedCount >= minGapBuffers {
                return .endGapTrim(keepBuffers: keepBuffers)
            }
            return .endGapEmitAll
        }

        return .stash
    }

    private func discriminatedLevel(_ features: TrimFeatureFrame, enterDB: Float, exitDB: Float) -> Float {
        switch parameters.discriminator {
        case .rms:
            return features.rmsDB
        case .heuristic, .vad:
            // VAD adds a retrospective veto at trim time (AudioReadTask side);
            // its provisional gating matches the heuristic. A fresh high-confidence
            // speech result also forces the gate open immediately.
            if parameters.discriminator == .vad,
               let confidence = features.vadSpeechConfidence,
               confidence > Float(parameters.vadSpeechConfidenceThreshold) {
                return exitDB + 1
            }

            guard features.rmsDB < enterDB else { return features.rmsDB }

            // quiet buffer: only count it as silence when it's noise-like.
            // Tonal content (music/reverb tails) has low spectral flatness.
            if features.spectralFlatness < Float(parameters.flatnessThreshold) {
                return exitDB + 1
            }
            // quiet but very high zero-crossing rate near the gate = trailing
            // fricatives; protect them
            if features.zeroCrossingRate > Float(parameters.zcrThreshold),
               features.rmsDB > enterDB - Float(parameters.zcrLevelMarginDB) {
                return exitDB + 1
            }
            return features.rmsDB
        }
    }
}
