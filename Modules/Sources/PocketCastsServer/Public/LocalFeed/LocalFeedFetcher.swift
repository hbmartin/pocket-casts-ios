import Foundation
import PocketCastsUtils

public enum LocalFeedError: Error {
    case invalidURL(String)
    case httpError(statusCode: Int)
}

public enum LocalFeedURL {
    public static func removingCredentials(from urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.user = nil
        components.password = nil
        return components.string ?? urlString
    }

    /// For log messages only: strips userinfo AND blanks every query value —
    /// `?token=…`-style feed auth must never reach the shareable diagnostic log.
    public static func redactedForLogging(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return "<unparseable feed url>" }
        components.user = nil
        components.password = nil
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { URLQueryItem(name: $0.name, value: "REDACTED") }
        }
        return components.string ?? "<unparseable feed url>"
    }

    /// The `user:password` userinfo of a feed URL, when present.
    public static func credentials(from urlString: String) -> (user: String, password: String)? {
        guard let components = URLComponents(string: urlString),
              let user = components.user, !user.isEmpty,
              let password = components.password else { return nil }
        return (user, password)
    }
}

/// Fetches and parses a feed over the network — no Pocket Casts servers involved.
///
/// Private feeds: per-user token URLs work untouched; `user:password@host` URLs are
/// converted to an HTTP Basic `Authorization` header. Because stored feed URLs are
/// credential-stripped, refreshes pass the credentials captured at subscribe time
/// (Keychain, see `LocalFeedCredentials`) via the `credentials` parameter.
public struct LocalFeedFetcher: Sendable {
    /// Cap on RFC 5005 `rel="next"` pages followed when back-filling a paged feed.
    public static let maxPages = 5

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches and parses the feed at `urlString`. When `followingPages` is true (the
    /// back-fill/subscribe path), `rel="next"` pages are followed — up to `maxPages`,
    /// stopping quietly on a page error so partial history still lands.
    /// `credentials` supplies HTTP Basic auth when the URL itself carries no userinfo.
    public func fetchFeed(url urlString: String, followingPages: Bool = false, credentials: (user: String, password: String)? = nil) async throws -> ParsedFeed {
        var merged = try await fetchPage(urlString, credentials: credentials)
        guard followingPages else { return merged }

        var visited: Set<String> = [urlString]
        var nextURL = merged.nextPageURL
        while let pageURL = nextURL, visited.count < Self.maxPages, !visited.contains(pageURL) {
            visited.insert(pageURL)
            guard let page = try? await fetchPage(pageURL, credentials: credentials) else { break }
            merged.items.append(contentsOf: page.items)
            nextURL = page.nextPageURL
        }
        merged.nextPageURL = nil
        return merged
    }

    private func fetchPage(_ urlString: String, credentials: (user: String, password: String)?) async throws -> ParsedFeed {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LocalFeedError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 60)
        let basicAuth = (url.user).flatMap { user in url.password.map { (user, $0) } } ?? credentials
        if let (user, password) = basicAuth,
           let encoded = "\(user):\(password)".data(using: .utf8) {
            request.setValue("Basic \(encoded.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            throw LocalFeedError.httpError(statusCode: httpResponse.statusCode)
        }

        return try FeedParser().parse(data: data)
    }
}
