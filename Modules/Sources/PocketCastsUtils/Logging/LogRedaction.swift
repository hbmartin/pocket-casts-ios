import Foundation

/// Scrubs secret-bearing URLs out of free-form log text before it leaves the
/// device (feedback reports, shared diagnostics). Log sites record full request
/// URLs, and private-feed enclosures can carry signed query tokens or
/// `user:password` userinfo. Scheme, host, and path are kept so the logs stay
/// diagnostic; userinfo is stripped, query parameter values are blanked (keys
/// are kept), and fragments are dropped.
///
/// This is the export-time counterpart to `LocalFeedURL.redactedForLogging`
/// (PocketCastsServer), which redacts a single known feed URL at log-write time.
public enum LogRedaction {
    /// Matches URL-shaped substrings in free text: a scheme, `://`, then
    /// everything up to whitespace or a delimiter that ends a URL in a log line.
    /// Computed because `Regex` is not Sendable; built once per `redactURLs` call.
    private static var urlPattern: Regex<Substring> { /[A-Za-z][A-Za-z0-9+.\-]*:\/\/[^\s"'<>`]+/ }

    /// Redacts every URL-shaped substring in `text`, leaving all other text
    /// untouched. Substrings that look like URLs but fail to parse are replaced
    /// with a safe placeholder so malformed credentials cannot escape.
    public static func redactURLs(in text: String) -> String {
        text.replacing(urlPattern) { match in
            redact(String(match.output))
        }
    }

    private static func redact(_ candidate: String) -> String {
        // Trailing sentence punctuation belongs to the surrounding log text,
        // not the URL — peel it off and reattach it after redaction.
        var url = Substring(candidate)
        var trailer = ""
        while let last = url.last, ".,;:!?)]}".contains(last) {
            trailer = String(last) + trailer
            url = url.dropLast()
        }

        guard var components = URLComponents(string: String(url)) else {
            return "<unparseable-url>" + trailer
        }

        components.user = nil
        components.password = nil
        components.fragment = nil
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map {
                URLQueryItem(name: $0.name, value: $0.value == nil ? nil : "REDACTED")
            }
        }

        guard let redacted = components.string else {
            return "<unparseable-url>" + trailer
        }
        return redacted + trailer
    }
}
