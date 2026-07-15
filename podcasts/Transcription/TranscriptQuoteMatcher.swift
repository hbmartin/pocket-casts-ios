import Foundation

/// Pure quote-to-transcript matching for inbound quote share links.
///
/// A shared quote was assembled from cue texts joined with single spaces, while
/// the transcript's plain text keeps its own whitespace (newlines between cues),
/// so literal substring search fails across cue boundaries. Matching instead
/// treats any whitespace run as equivalent (`\s+`) and is case-insensitive; when
/// the full quote doesn't match (outbound truncation, transcript source drift),
/// progressively shorter word prefixes are tried.
nonisolated enum TranscriptQuoteMatcher {

    /// Longest word prefix ever matched against; keeps the regex bounded.
    private static let maxPrefixWords = 12

    /// The UTF-16 range of the quote (or its longest matching word prefix) in
    /// `text`, or nil when nothing matches. Tries the quote capped to
    /// ``maxPrefixWords`` first, then shorter rungs (6, then 3 words).
    static func range(ofQuote quote: String, in text: String) -> NSRange? {
        let words = quote
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !words.isEmpty else { return nil }

        var counts = [min(words.count, maxPrefixWords)]
        for rung in [6, 3] where rung < counts[0] {
            counts.append(rung)
        }

        for count in counts {
            if let range = match(words: Array(words.prefix(count)), in: text) {
                return range
            }
        }
        return nil
    }

    private static func match(words: [String], in text: String) -> NSRange? {
        guard !words.isEmpty else { return nil }
        let pattern = words
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: fullRange)?.range
    }
}
