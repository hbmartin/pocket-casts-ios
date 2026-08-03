import Foundation

/// Pure cue-window logic for smart highlights: given a transcript's cues and its
/// plain text, selects the cues intersecting the window around a bookmark's
/// position and assembles a shareable excerpt.
nonisolated enum HighlightExcerptBuilder {
    /// How far before the bookmark position the excerpt window reaches. Listeners
    /// bookmark just after hearing something, so the window leans backwards.
    static let leadingWindow: TimeInterval = 10

    /// How far after the bookmark position the excerpt window reaches.
    static let trailingWindow: TimeInterval = 5

    struct Excerpt: Equatable, Sendable {
        let text: String

        /// Start of the earliest intersecting cue (transcript time domain).
        let startTime: TimeInterval

        /// End of the latest intersecting cue (transcript time domain).
        let endTime: TimeInterval
    }

    /// Builds the excerpt around `time` (in the transcript's own time domain).
    ///
    /// - Parameters:
    ///   - time: The anchor to build the window around.
    ///   - cues: The transcript's cues; text is resolved via `characterRange`.
    ///   - plainText: The transcript text the cue ranges index into (UTF-16 offsets).
    /// - Returns: nil when no cue intersects the window or the window text is empty.
    static func excerpt(
        around time: TimeInterval,
        cues: [TranscriptCue],
        plainText: String,
        leading: TimeInterval = leadingWindow,
        trailing: TimeInterval = trailingWindow
    ) -> Excerpt? {
        let windowStart = max(0, time - leading)
        let windowEnd = time + trailing
        let intersecting = cues.filter { $0.endTime >= windowStart && $0.startTime <= windowEnd }
        return assemble(intersecting, fullText: plainText as NSString, fallbackTime: time)
    }

    /// Collapses runs of whitespace/newlines to single spaces and trims the ends.
    static func normalizedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Smart window (sentence-snapped reach-back)

    /// How far before the anchor the smart window may reach when the speech run
    /// is continuous: listeners tap well after the thought started.
    static let maxLeadingReach: TimeInterval = 45

    /// How far after the anchor the smart window may reach to finish the sentence
    /// in flight.
    static let maxTrailingReach: TimeInterval = 15

    /// An inter-cue silence at least this long is treated as a boundary (a pause
    /// or speaker turn) that the smart window never crosses.
    static let boundaryGap: TimeInterval = 1.5

    /// Builds the enrichment excerpt around `time`, snapping to sentence-ish
    /// boundaries instead of wall-clock edges: starting from the base window
    /// (`leadingWindow`/`trailingWindow`), the selection grows backwards to the
    /// nearest sentence start (terminal punctuation on the preceding cue, a
    /// `boundaryGap` silence, or the transcript start) within `maxLeadingReach`,
    /// and forwards to the end of the sentence in flight within
    /// `maxTrailingReach`.
    ///
    /// Used by the enrichment pipeline only — quote links and clip spans keep the
    /// compact explicit-window `excerpt(around:)` behavior.
    static func smartExcerpt(
        around time: TimeInterval,
        cues: [TranscriptCue],
        plainText: String
    ) -> Excerpt? {
        let windowStart = max(0, time - leadingWindow)
        let windowEnd = time + trailingWindow

        // Cues are ordered in every transcript source, but sort defensively:
        // the boundary walk below depends on adjacency.
        let ordered = cues.sorted { $0.startTime < $1.startTime }
        let seedIndexes = ordered.indices.filter {
            ordered[$0].endTime >= windowStart && ordered[$0].startTime <= windowEnd
        }
        guard let firstSeed = seedIndexes.first, let lastSeed = seedIndexes.last else { return nil }

        let fullText = plainText as NSString

        // Reach back cue-by-cue until a sentence start, a silence boundary, or the
        // leading cap. The cap is checked against the candidate's start so a cue
        // straddling it is still taken whole (boundaries beat wall-clock).
        var start = firstSeed
        while start > ordered.startIndex {
            let previous = ordered.index(before: start)
            guard ordered[previous].startTime >= time - maxLeadingReach else { break }
            guard ordered[start].startTime - ordered[previous].endTime < boundaryGap else { break }
            guard !endsSentence(ordered[previous], in: fullText) else { break }
            start = previous
        }

        // Reach forward to the end of the sentence in flight, same rules mirrored.
        var end = lastSeed
        while end < ordered.index(before: ordered.endIndex) {
            guard !endsSentence(ordered[end], in: fullText) else { break }
            let next = ordered.index(after: end)
            guard ordered[next].endTime <= time + maxTrailingReach else { break }
            guard ordered[next].startTime - ordered[end].endTime < boundaryGap else { break }
            end = next
        }

        return assemble(Array(ordered[start...end]), fullText: fullText, fallbackTime: time)
    }

    /// Builds the excerpt for an explicit `[start, end]` range (transcript time
    /// domain) — the trim editor's save path and caption sourcing.
    static func excerpt(
        in range: ClosedRange<TimeInterval>,
        cues: [TranscriptCue],
        plainText: String
    ) -> Excerpt? {
        let intersecting = cues
            .filter { $0.endTime >= range.lowerBound && $0.startTime <= range.upperBound }
            .sorted { $0.startTime < $1.startTime }
        return assemble(intersecting, fullText: plainText as NSString, fallbackTime: range.lowerBound)
    }

    /// Recovers the stored excerpt's cue window `[start, end]` from the pieces a
    /// bookmark actually persists (excerpt text + window end): starting at the
    /// cue whose end matches `endTime`, cues are walked backwards while their
    /// accumulated text stays a suffix of the stored excerpt, until it matches
    /// exactly. Deterministic against the same transcript; nil when the
    /// transcript changed enough that no window reproduces the text (the trim
    /// editor then falls back to the anchor-based default window).
    static func recoveredWindow(
        excerpt: String,
        endTime: TimeInterval,
        cues: [TranscriptCue],
        plainText: String
    ) -> ClosedRange<TimeInterval>? {
        let target = normalizedWhitespace(excerpt)
        guard !target.isEmpty else { return nil }

        let ordered = cues.sorted { $0.startTime < $1.startTime }
        let fullText = plainText as NSString

        // The window's last cue: the one whose end lands on the stored endTime
        // (small tolerance for float round-trips through sync).
        let exactMatch = ordered.lastIndex { abs($0.endTime - endTime) < 1.5 }
        let looseMatch = ordered.lastIndex { $0.endTime <= endTime + 1.5 }
        guard let endIndex = exactMatch ?? looseMatch else { return nil }

        var accumulated = ""
        var index = endIndex
        while true {
            let cue = ordered[index]
            guard cue.characterRange.location != NSNotFound,
                  NSMaxRange(cue.characterRange) <= fullText.length else {
                return nil
            }
            let piece = normalizedWhitespace(fullText.substring(with: cue.characterRange))
            accumulated = piece.isEmpty ? accumulated : (accumulated.isEmpty ? piece : "\(piece) \(accumulated)")

            if accumulated == target {
                return cue.startTime...ordered[endIndex].endTime
            }
            guard target.hasSuffix(accumulated), index > ordered.startIndex else { return nil }
            index = ordered.index(before: index)
        }
    }

    /// True when the cue's text ends a sentence (terminal punctuation, optionally
    /// followed by closing quotes/brackets).
    static func endsSentence(_ cue: TranscriptCue, in fullText: NSString) -> Bool {
        guard cue.characterRange.location != NSNotFound,
              NSMaxRange(cue.characterRange) <= fullText.length else {
            return false
        }
        let text = normalizedWhitespace(fullText.substring(with: cue.characterRange))
        guard let last = text.unicodeScalars.reversed().first(where: { !closingTrailers.contains($0) }) else {
            return false
        }
        return sentenceTerminators.contains(last)
    }

    private static let sentenceTerminators = CharacterSet(charactersIn: ".!?…。！？")
    private static let closingTrailers = CharacterSet(charactersIn: "\"'”’»)]}")

    /// Shared tail: resolves cue text through `characterRange` and assembles the
    /// excerpt payload. nil when nothing resolves to visible text.
    private static func assemble(_ cues: [TranscriptCue], fullText: NSString, fallbackTime: TimeInterval) -> Excerpt? {
        guard !cues.isEmpty else { return nil }

        let pieces: [String] = cues.compactMap { cue in
            guard cue.characterRange.location != NSNotFound,
                  NSMaxRange(cue.characterRange) <= fullText.length else {
                return nil
            }
            let piece = normalizedWhitespace(fullText.substring(with: cue.characterRange))
            return piece.isEmpty ? nil : piece
        }

        let text = pieces.joined(separator: " ")
        guard !text.isEmpty else { return nil }

        return Excerpt(
            text: text,
            startTime: cues.map(\.startTime).min() ?? fallbackTime,
            endTime: cues.map(\.endTime).max() ?? fallbackTime
        )
    }
}
