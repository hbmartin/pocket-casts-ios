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
        guard !intersecting.isEmpty else { return nil }

        let fullText = plainText as NSString
        let pieces: [String] = intersecting.compactMap { cue in
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
            startTime: intersecting.map(\.startTime).min() ?? time,
            endTime: intersecting.map(\.endTime).max() ?? time
        )
    }

    /// Collapses runs of whitespace/newlines to single spaces and trims the ends.
    static func normalizedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
