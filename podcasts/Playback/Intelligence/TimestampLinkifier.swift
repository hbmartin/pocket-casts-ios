import Foundation

/// Finds spoken-timestamp mentions ("3:45", "12:04", "1:02:33") in summary
/// text and turns them into tappable ranges (plans/AI UX Improvements.md
/// Phase 2). Pure string logic — the view layer decides what the taps do.
nonisolated enum TimestampLinkifier {

    /// A timestamp mention found in the source text.
    struct Match: Equatable, Sendable {
        /// UTF-16 range (NSRange convention) into the source string.
        let nsRange: NSRange
        /// The matched text exactly as written (e.g. "1:02:33").
        let text: String
        /// The parsed time in seconds.
        let seconds: TimeInterval
    }

    /// mm:ss or h:mm:ss word-bounded timestamps.
    static let pattern = #"\b(?:\d{1,2}:)?\d{1,2}:\d{2}\b"#

    private static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern)

    /// All valid timestamp mentions in `text`, in order of appearance.
    /// Regex hits that aren't real clock times (e.g. "12:75") are dropped.
    static func matches(in text: String) -> [Match] {
        guard let regex else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: fullRange).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let matchedText = String(text[range])
            guard let seconds = seconds(from: matchedText) else { return nil }
            return Match(nsRange: result.range, text: matchedText, seconds: seconds)
        }
    }

    /// Parses "mm:ss" / "h:mm:ss" into seconds. Returns nil when a component
    /// isn't a valid clock value (seconds/minutes must be under 60 in any
    /// position that has a more significant neighbour).
    static func seconds(from text: String) -> TimeInterval? {
        let components = text.split(separator: ":").map(String.init)
        guard components.count == 2 || components.count == 3,
              components.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        let values = components.compactMap { Int($0) }
        guard values.count == components.count else { return nil }

        // Every component below the most significant one must be a valid 0-59 clock value.
        guard values.dropFirst().allSatisfy({ (0...59).contains($0) }),
              values[0] >= 0 else {
            return nil
        }

        return TimeInterval(values.reduce(0) { $0 * 60 + $1 })
    }

    /// Builds the summary text as an `AttributedString` with each timestamp
    /// mention carrying a `.link` produced by `urlBuilder` (mentions where the
    /// builder returns nil stay plain). Splitting on UTF-16 ranges of the
    /// source string sidesteps `String.Index`/`AttributedString.Index` conversion.
    static func linkified(_ text: String, urlBuilder: (TimeInterval) -> URL?) -> AttributedString {
        let matches = matches(in: text)
        guard !matches.isEmpty else { return AttributedString(text) }

        let source = text as NSString
        var output = AttributedString()
        var cursor = 0

        for match in matches {
            if match.nsRange.location > cursor {
                let plain = source.substring(with: NSRange(location: cursor, length: match.nsRange.location - cursor))
                output += AttributedString(plain)
            }
            var linkText = AttributedString(match.text)
            if let url = urlBuilder(match.seconds) {
                linkText.link = url
            }
            output += linkText
            cursor = NSMaxRange(match.nsRange)
        }

        if cursor < source.length {
            output += AttributedString(source.substring(from: cursor))
        }
        return output
    }
}
