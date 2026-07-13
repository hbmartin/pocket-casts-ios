import Foundation

/// Finds the inter-word silence nearest a target time from a window of
/// per-hop RMS levels, so Smart Resume can start playback at a word boundary
/// instead of mid-word. Pure logic — no audio APIs — driven by
/// `ResumeSnapAnalyzer` and unit-testable with synthetic level arrays.
nonisolated struct SilenceGapFinder {
    struct Parameters {
        /// Seconds before the target that the analysis window (and a snap candidate) may extend.
        var windowBefore: TimeInterval = 2.5
        /// Seconds after the target that the analysis window (and a snap candidate) may extend.
        var windowAfter: TimeInterval = 0.5
        /// Analysis hop between successive RMS measurements.
        var hopDuration: TimeInterval = 0.05
        /// Minimum run of below-threshold audio that counts as an inter-word gap.
        var minGapDuration: TimeInterval = 0.15
        /// How far before the detected speech onset the snap point sits, absorbing
        /// VBR seek error and player priming skew.
        var onsetPad: TimeInterval = 0.15
        /// Largest |snap − raw| adjustment the resume path accepts when validating
        /// a stored candidate.
        var maxAdjustment: TimeInterval = 2.5
        /// Minimum dynamic range between the noise floor and speech level; below
        /// this the window is treated as music/tone and left alone.
        var minDynamicRangeDB: Float = 12
        /// Where the silence threshold sits between the floor (0) and speech level (1).
        var thresholdFraction: Float = 0.3
    }

    /// Returns the snap time nearest `target`, or nil when the window has no
    /// usable inter-word gap.
    ///
    /// - Parameters:
    ///   - levelsDB: per-hop RMS levels in dBFS covering the analysis window
    ///   - windowStart: the time (in episode seconds) of the first hop
    ///   - hopDuration: the hop between successive levels
    ///   - target: the raw resume time the caller wants to snap
    static func snapTime(levelsDB: [Float], windowStart: TimeInterval, hopDuration: TimeInterval, target: TimeInterval, parameters: Parameters = Parameters()) -> TimeInterval? {
        guard hopDuration > 0, !levelsDB.isEmpty else { return nil }

        // estimate the noise floor and speech level from the level distribution
        let sortedLevels = levelsDB.sorted()
        let noiseFloor = percentile(of: sortedLevels, fraction: 0.1)
        let speechLevel = percentile(of: sortedLevels, fraction: 0.9)
        let dynamicRange = speechLevel - noiseFloor

        // low dynamic range means music or a continuous tone: nothing to snap to
        guard dynamicRange >= parameters.minDynamicRangeDB else { return nil }

        let threshold = noiseFloor + parameters.thresholdFraction * dynamicRange
        let minGapHops = max(1, Int((parameters.minGapDuration / hopDuration).rounded()))

        // gaps are runs of at least minGapHops below the threshold followed by a
        // real speech onset; runs still open at the end of the window are discarded
        var candidates = [TimeInterval]()
        var runStart: Int?
        for index in 0 ..< levelsDB.count {
            if levelsDB[index] < threshold {
                if runStart == nil { runStart = index }
                continue
            }

            guard let start = runStart else { continue }
            runStart = nil

            guard index - start >= minGapHops else { continue }

            let gapStart = windowStart + TimeInterval(start) * hopDuration
            let onset = windowStart + TimeInterval(index) * hopDuration
            let snap = max(gapStart, onset - parameters.onsetPad)
            if snap >= target - parameters.windowBefore, snap <= target + parameters.windowAfter {
                candidates.append(snap)
            }
        }

        // nearest to the target; ties resolve to the earlier candidate
        return candidates.min { lhs, rhs in
            let lhsDistance = abs(lhs - target)
            let rhsDistance = abs(rhs - target)
            if lhsDistance == rhsDistance { return lhs < rhs }

            return lhsDistance < rhsDistance
        }
    }

    private static func percentile(of sortedLevels: [Float], fraction: Double) -> Float {
        let index = Int((Double(sortedLevels.count - 1) * fraction).rounded())

        return sortedLevels[index]
    }
}
