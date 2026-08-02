import Foundation

/// The listener's tour-length choice (Highlights S9).
nonisolated enum TourLength: String, CaseIterable, Sendable {
    /// ~5 minutes (or half the episode when it's shorter than 10 minutes).
    case quick
    /// ~25% of the episode — the Snipd-style default.
    case standard
    /// ~50% of the episode.
    case deep

    func budget(forDuration duration: TimeInterval) -> TimeInterval {
        switch self {
        case .quick: min(300, duration * 0.5)
        case .standard: duration * 0.25
        case .deep: duration * 0.5
        }
    }

    var displayableTitle: String {
        switch self {
        case .quick: L10n.tourLengthQuick
        case .standard: L10n.tourLengthStandard
        case .deep: L10n.tourLengthDeep
        }
    }
}

/// One stop on the tour: a salient segment plus its spoken bridge line.
nonisolated struct TourStop: Equatable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let title: String
    /// Spoken before seeking to this stop ("Next: …"). Deterministic, composed
    /// at plan time — never model-generated at tour runtime.
    let bridgeLine: String

    var duration: TimeInterval { endTime - startTime }
}

/// A planned tour: chronological stops + intro/outro lines.
nonisolated struct TourPlan: Equatable, Sendable {
    let stops: [TourStop]
    let introLine: String
    let outroLine: String
    /// Total listening time across stops (what the picker previews).
    var totalDuration: TimeInterval { stops.reduce(0) { $0 + $1.duration } }
}

/// Pure budget math (Highlights S9, ADR-0018): serves any length preset from
/// ONE ranked candidate list — greedy prefix-by-rank under the budget, then
/// chronological reorder.
nonisolated enum TourPlanner {
    /// - Returns: nil when no segment fits the budget (callers show the
    ///   preparation-failed state).
    static func plan(
        segments: [SalientSegment],
        length: TourLength,
        episodeDuration: TimeInterval,
        episodeTitle: String
    ) -> TourPlan? {
        let budget = length.budget(forDuration: episodeDuration)

        // Greedy by rank: take segments in salience order while they fit,
        // skipping any that individually overflow — but never end up empty
        // when at least one segment exists (the top rank always plays).
        var chosen: [SalientSegment] = []
        var spent: TimeInterval = 0
        for segment in segments.sorted(by: { $0.rank < $1.rank }) {
            let duration = segment.endTime - segment.startTime
            if spent + duration <= budget {
                chosen.append(segment)
                spent += duration
            }
        }
        if chosen.isEmpty, let top = segments.min(by: { $0.rank < $1.rank }) {
            chosen = [top]
        }
        guard !chosen.isEmpty else { return nil }

        chosen.sort { $0.startTime < $1.startTime }

        let stops = chosen.map { segment in
            TourStop(
                startTime: segment.startTime,
                endTime: segment.endTime,
                title: segment.title,
                bridgeLine: L10n.tourBridgeLine(segment.title)
            )
        }

        return TourPlan(
            stops: stops,
            introLine: L10n.tourIntroLine(String(stops.count), episodeTitle),
            outroLine: L10n.tourOutroLine
        )
    }
}
