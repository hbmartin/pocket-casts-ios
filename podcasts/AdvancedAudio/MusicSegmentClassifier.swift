import Foundation

/// Hysteresis state machine deciding when playback is inside a music segment,
/// fed per-buffer with the sound classifier's speech/music confidences
/// (Deferred Item 14 — adaptive effects switching).
///
/// Music must dominate for `enterSustain` seconds before the state flips on, and
/// stop dominating for `exitSustain` seconds before it flips off, so stings and
/// brief musical beds don't toggle the effects chain. Observations with no
/// classifier coverage (nil) reset the pending streak and hold the current
/// state — no information is never a reason to switch.
nonisolated struct MusicSegmentClassifier {
    struct Parameters {
        /// Minimum "music" confidence for an observation to count as music-dominant.
        var musicConfidenceThreshold: Float = 0.7
        /// Seconds music must stay dominant before effects switch off.
        var enterSustain: TimeInterval = 5
        /// Seconds music must stay non-dominant before effects switch back on.
        var exitSustain: TimeInterval = 3
    }

    let parameters: Parameters

    private(set) var isMusicActive = false
    /// When the current opposing streak (music while inactive, non-music while
    /// active) started; nil when no streak is running.
    private var streakStart: TimeInterval?
    /// When the active music segment started (telemetry).
    private(set) var segmentStart: TimeInterval?
    /// Duration of the segment that just ended; set on the flip to inactive (telemetry).
    private(set) var endedSegmentDuration: TimeInterval?

    init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
    }

    /// Feeds one observation at playback time `time` (seconds). Returns true when
    /// the music-active state flipped.
    mutating func analyze(speechConfidence: Float?, musicConfidence: Float?, at time: TimeInterval) -> Bool {
        guard let musicConfidence else {
            streakStart = nil
            return false
        }

        let musicDominant = musicConfidence >= parameters.musicConfidenceThreshold
            && musicConfidence > (speechConfidence ?? 0)

        if isMusicActive == musicDominant {
            // The observation agrees with the current state: no streak to build.
            streakStart = nil
            return false
        }

        guard let start = streakStart else {
            streakStart = time
            return false
        }
        // Seeks rewind time; restart the streak rather than measuring a negative span.
        guard time >= start else {
            streakStart = time
            return false
        }

        let sustain = isMusicActive ? parameters.exitSustain : parameters.enterSustain
        guard time - start >= sustain else { return false }

        isMusicActive = musicDominant
        if isMusicActive {
            segmentStart = start
            endedSegmentDuration = nil
        } else {
            // The segment effectively ended when music stopped dominating —
            // the start of the exit streak, not the moment the flip confirmed.
            endedSegmentDuration = segmentStart.map { max(0, start - $0) }
            segmentStart = nil
        }
        streakStart = nil
        return true
    }

    /// Resets all streak state (seeks and analyzer rebuilds).
    mutating func reset() {
        isMusicActive = false
        streakStart = nil
        segmentStart = nil
        endedSegmentDuration = nil
    }
}
