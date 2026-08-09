import Foundation
import PocketCastsUtils

/// Minimal Readwise API v2 client (Highlights S6). Third-party origin, so this
/// deliberately does NOT ride the first-party `URLConnection` boundary (origin
/// policy and App Attest apply only to the fork backend).
nonisolated struct ReadwiseClient: Sendable {
    static let defaultRetryAfter: TimeInterval = 60
    static let maximumRetryAfter: TimeInterval = 60 * 60

    /// One highlight in Readwise's batch-create shape. `highlight_url` carries
    /// the bookmark identity, making re-pushes update-in-place (Readwise
    /// dedupes on it) instead of duplicating.
    struct Highlight: Codable, Equatable, Sendable {
        let text: String
        let title: String
        let author: String?
        let sourceType: String
        let sourceUrl: String?
        let highlightUrl: String?
        let note: String?
        let highlightedAt: String?

        enum CodingKeys: String, CodingKey {
            case text, title, author, note
            case sourceType = "source_type"
            case sourceUrl = "source_url"
            case highlightUrl = "highlight_url"
            case highlightedAt = "highlighted_at"
        }
    }

    enum ClientError: Error, Equatable {
        case missingToken
        case unauthorized
        /// Retry after the given delay (Readwise rate limit).
        case rateLimited(retryAfter: TimeInterval)
        case httpError(Int)
    }

    var session: URLSession = .shared
    var baseURL = URL(string: "https://readwise.io/api/v2")!

    /// GET /auth — 204 when the token is valid.
    func validateToken(_ token: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/"))
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }

    /// POST /highlights — batch create/update.
    func push(_ highlights: [Highlight], token: String) async throws {
        guard !highlights.isEmpty else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("highlights/"))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["highlights": highlights])

        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.httpError(-1) }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw ClientError.unauthorized
        case 429:
            let requestedDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            let retryAfter: TimeInterval
            if let requestedDelay, requestedDelay.isFinite {
                retryAfter = min(max(requestedDelay, 0), Self.maximumRetryAfter)
            } else {
                retryAfter = Self.defaultRetryAfter
            }
            throw ClientError.rateLimited(retryAfter: retryAfter)
        default:
            throw ClientError.httpError(http.statusCode)
        }
    }

    /// Builds the Readwise payload for one highlight. Pure, unit-tested.
    static func highlight(
        excerpt: String?,
        bookmarkTitle: String,
        bookmarkUuid: String,
        time: TimeInterval,
        created: Date,
        tags: [String],
        episodeTitle: String,
        podcastTitle: String?,
        shareLink: String?
    ) -> Highlight {
        // Readwise renders `.tag` tokens in notes as tags.
        var noteParts: [String] = []
        if excerpt != nil, !bookmarkTitle.isEmpty, bookmarkTitle != L10n.bookmarkDefaultTitle {
            noteParts.append(bookmarkTitle)
        }
        if !tags.isEmpty {
            noteParts.append(tags.map { ".\($0.components(separatedBy: .whitespacesAndNewlines).joined(separator: "-"))" }.joined(separator: " "))
        }

        let formatter = ISO8601DateFormatter()

        return Highlight(
            text: excerpt ?? bookmarkTitle,
            title: episodeTitle,
            author: podcastTitle,
            sourceType: "podcast",
            sourceUrl: shareLink,
            highlightUrl: shareLink.map { "\($0)&hl=\(bookmarkUuid)" },
            note: noteParts.isEmpty ? nil : noteParts.joined(separator: "\n"),
            highlightedAt: formatter.string(from: created)
        )
    }
}
