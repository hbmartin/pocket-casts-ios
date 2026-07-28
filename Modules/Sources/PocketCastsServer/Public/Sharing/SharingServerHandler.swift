import Foundation
import PocketCastsUtils

public final class SharingServerHandler: Sendable {
    private static let timeout: TimeInterval = 20

    public static let shared = SharingServerHandler()

    private let tokenHelper: TokenHelper

    private let urlConnection: URLConnection

    init(tokenHelper: TokenHelper = .shared, urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.tokenHelper = tokenHelper
        self.urlConnection = urlConnection
    }

    public struct PodcastShareInfo: Codable {
        public let title: String
        public let description: String?
        public let podcasts: [String]

        public init(title: String, description: String, podcasts: [String]) {
            self.title = title
            self.description = description
            self.podcasts = podcasts
        }
    }

    public struct PodcastList: Decodable, Sendable {
        public let title: String?
        public let listDescription: String?
        public let podcasts: [ListPodcast]?

        public enum CodingKeys: String, CodingKey {
            case title, podcasts
            case listDescription = "description"
        }
    }

    public struct ListPodcast: Decodable, Sendable {
        public let title: String?
        public let uuid: String?
        public let podcastDescription: String?
        public let author: String?
        public let iTunesId: Int?

        public enum CodingKeys: String, CodingKey {
            case title, uuid, author
            case podcastDescription = "description"
            case iTunesId = "collection_id"
        }
    }

    private struct PodcastShareRequest: Codable {
        let title: String
        let description: String?
        let podcasts: [[String: String]]
    }

    private struct PodcastShareResponse: Decodable {
        var status: String?
        var result: PodcastShareResult?
    }

    private struct PodcastShareResult: Decodable {
        var shareUrl: String?

        enum CodingKeys: String, CodingKey {
            case shareUrl = "share_url"
        }
    }

    /// Outcome of a share-list publish. `requiresSignIn` is produced only on the
    /// bearer path when no user is signed in — the UI should route to sign-in
    /// instead of showing a generic failure.
    public enum PodcastShareListResult: Sendable {
        case shared(url: String)
        case failed
        case requiresSignIn
    }

    public func sharePodcastList(listInfo: PodcastShareInfo, completion: @escaping @Sendable (PodcastShareListResult) -> Void) {
        let url = ServerHelper.asUrl(ServerConstants.Urls.sharing() + "share/list")

        let convertedPodcasts = listInfo.podcasts.compactMap { uuid -> [String: String] in
            ["uuid": uuid]
        }
        let shareRequest = PodcastShareRequest(title: listInfo.title, description: listInfo.description, podcasts: convertedPodcasts)

        guard SyncManager.isUserLoggedIn() else {
            completion(.requiresSignIn)
            return
        }

        guard let request = ServerHelper.createJsonRequest(url: url, params: shareRequest, timeout: SharingServerHandler.timeout, cachePolicy: .useProtocolCachePolicy) else {
            completion(.failed)

            return
        }

        tokenHelper.callSecureUrl(request: request) { response, data, error in
            let shareUrl = Self.parseShareResponse(statusCode: response?.statusCode, data: data, error: error)
            completion(shareUrl.map { .shared(url: $0) } ?? .failed)
        }
    }

    private static func parseShareResponse(statusCode: Int?, data: Data?, error: Error?) -> String? {
        guard statusCode == ServerConstants.HttpConstants.ok, let data, error == nil else {
            return nil
        }

        return try? JSONDecoder().decode(PodcastShareResponse.self, from: data).result?.shareUrl
    }

    public func loadList(listUrl: URL, completion: @escaping @Sendable (_ podcastList: PodcastList?) -> Void) {
        urlConnection.send(request: URLRequest(url: listUrl)) { data, response, error in
            guard (response as? HTTPURLResponse)?.statusCode == ServerConstants.HttpConstants.ok, let data, error == nil else {
                completion(nil)

                return
            }

            do {
                let podcastList = try JSONDecoder().decode(PodcastList.self, from: data)
                completion(podcastList)
            } catch {
                completion(nil)
            }
        }
    }
}
