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
}

/// Fetches and parses a feed over the network — no Pocket Casts servers involved.
///
/// Private feeds are supported to the extent their credentials live in the stored feed
/// URL: per-user token URLs work untouched, and `user:password@host` URLs are converted
/// to an HTTP Basic `Authorization` header. A credential-entry UI is a follow-up.
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
    public func fetchFeed(url urlString: String, followingPages: Bool = false) async throws -> ParsedFeed {
        var merged = try await fetchPage(urlString)
        guard followingPages else { return merged }

        var visited: Set<String> = [urlString]
        var nextURL = merged.nextPageURL
        while let pageURL = nextURL, visited.count < Self.maxPages, !visited.contains(pageURL) {
            visited.insert(pageURL)
            guard let page = try? await fetchPage(pageURL) else { break }
            merged.items.append(contentsOf: page.items)
            nextURL = page.nextPageURL
        }
        merged.nextPageURL = nil
        return merged
    }

    private func fetchPage(_ urlString: String) async throws -> ParsedFeed {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LocalFeedError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 60)
        if let user = url.user, let password = url.password,
           let credentials = "\(user):\(password)".data(using: .utf8) {
            request.setValue("Basic \(credentials.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            throw LocalFeedError.httpError(statusCode: httpResponse.statusCode)
        }

        return try FeedParser().parse(data: data)
    }
}
