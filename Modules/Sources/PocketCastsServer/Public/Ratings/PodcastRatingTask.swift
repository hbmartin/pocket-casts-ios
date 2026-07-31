import Foundation
import PocketCastsDataModel

public struct PodcastRating: Codable {
    public let total: Int
    public let average: Double
}

public struct PodcastRatingTask {
    private let urlConnection: URLConnection

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.urlConnection = urlConnection
    }

    public init(session: URLSession) {
        self.init(urlConnection: URLConnection(handler: session))
    }

    /// Retrieves the star rating and total for a single podcast
    public func retrieve(for podcastUuid: String, ignoringCache: Bool) async throws -> PodcastRating? {
        let urlString = "\(ServerConstants.Urls.cache())podcast/rating/\(podcastUuid)"
        let task = JSONDecodableURLTask<PodcastRating>(urlConnection: urlConnection)
        let cachePolicy: URLRequest.CachePolicy = ignoringCache ? .reloadIgnoringLocalAndRemoteCacheData : .useProtocolCachePolicy
        return try await task.get(urlString: urlString, cachePolicy: cachePolicy)
    }
}
