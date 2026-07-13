import Foundation

/// Retry-After handling for HTTP 429 responses (RFC 9110 §10.2.3) on token acquisition
/// and the generic secure-call paths. The server's abuse controls (plan workstreams A/B)
/// return 429 + Retry-After; the client honors the hint with a single capped retry.
extension HTTPURLResponse {
    /// The longest the client is willing to wait out a Retry-After hint.
    static let maximumRetryAfterDelay: TimeInterval = 60
    /// Delay used when a 429 arrives without a parseable Retry-After header.
    static let defaultRetryAfterDelay: TimeInterval = 1

    /// Parses the `Retry-After` header, which is either delay-seconds or an HTTP-date.
    /// Returns nil when the header is absent or unparseable; never returns a negative
    /// value or one above `maximum`.
    func retryAfterInterval(maximum: TimeInterval = HTTPURLResponse.maximumRetryAfterDelay) -> TimeInterval? {
        guard let rawValue = value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              !rawValue.isEmpty
        else {
            return nil
        }

        if let seconds = TimeInterval(rawValue) {
            guard seconds >= 0 else { return nil }
            return min(seconds, maximum)
        }

        // HTTP-date form, e.g. "Wed, 21 Oct 2015 07:28:00 GMT" (IMF-fixdate, RFC 9110 §5.6.7).
        // Built per call: DateFormatter isn't Sendable and 429s are rare.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: rawValue) else {
            return nil
        }

        return min(max(date.timeIntervalSinceNow, 0), maximum)
    }

    /// The delay to wait before the single retry of a rate-limited (429) request:
    /// the capped Retry-After hint, or a small default when the server didn't send one.
    func tooManyRequestsRetryDelay() -> TimeInterval {
        retryAfterInterval() ?? HTTPURLResponse.defaultRetryAfterDelay
    }
}
