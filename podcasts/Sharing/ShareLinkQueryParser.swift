import Foundation

/// Pure query parsing for inbound share links: the `t` (timestamp) and `q`
/// (quote) parameters. Extracted from `AppDelegate.openSharePath` so the
/// parsing rules are testable; `t` semantics are unchanged from the original
/// inline parsing (a `t=start,end` clip range fails `Double.init` and reads
/// as no timestamp, as before).
nonisolated enum ShareLinkQueryParser {

    /// Inbound quotes longer than this are dropped rather than truncated — an
    /// oversized value is not something this app's share flow produces.
    static let maxInboundQuoteLength = 500

    static func timestampAndQuote(from path: String) -> (timestamp: Double?, quote: String?) {
        guard let queryItems = URLComponents(string: path)?.queryItems else {
            return (nil, nil)
        }

        let timestamp = queryItems.first { $0.name == "t" }?.value.flatMap(Double.init)

        let quote: String? = queryItems.first { $0.name == "q" }?.value.flatMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maxInboundQuoteLength else { return nil }
            return trimmed
        }

        return (timestamp, quote)
    }
}
