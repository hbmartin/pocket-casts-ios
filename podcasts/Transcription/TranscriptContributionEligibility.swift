import Foundation
import PocketCastsDataModel

/// Pure eligibility rules for the transcript-contribution pipeline
/// (docs/TranscriptContributions.md §1, CONTEXT.md "Eligible episode").
/// Kept side-effect free so the truth table is directly unit-testable.
nonisolated enum TranscriptContributionEligibility {
    /// Whether the episode's transcripts may be contributed or sighted.
    ///
    /// Eligible iff the episode is a podcast `Episode` (never a `UserEpisode` —
    /// uploaded files are private by definition) and its podcast row exists.
    /// All podcasts come from the server catalog, so every podcast episode is
    /// public by construction.
    static func isEligible(episode: BaseEpisode?, podcast: Podcast?) -> Bool {
        guard let episode, episode is Episode, podcast != nil else { return false }
        return true
    }

    /// Query-item names that smell like credentials or signed-URL parameters.
    /// Matched case-insensitively as a substring of the name.
    private static let tokenNamePattern = "token|sig|signature|key|auth|session|expires|policy"

    /// The token-free rule for sighted transcript URLs.
    ///
    /// A URL may be sighted only when it carries no credentials or access
    /// tokens. A URL is rejected when any of these hold:
    ///
    /// - it does not parse as a URL,
    /// - it carries userinfo (`user:pass@host`),
    /// - any query item's name matches `(?i)(token|sig|signature|key|auth|session|expires|policy)`,
    /// - any query item's value is 16 or more characters (long opaque values
    ///   are assumed to be signatures/tokens regardless of their name).
    ///
    /// The server re-validates; this is the client-side enforcement
    /// (docs/TranscriptContributions.md §1 and §3).
    static func isTokenFreeURL(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString) else { return false }
        if components.user != nil || components.password != nil { return false }

        for item in components.queryItems ?? [] {
            if item.name.range(of: tokenNamePattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return false
            }
            if let value = item.value, value.count >= 16 {
                return false
            }
        }
        return true
    }
}
