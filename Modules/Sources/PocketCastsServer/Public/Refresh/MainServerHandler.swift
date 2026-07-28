import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

protocol BaseRequest: Encodable {
    var device: String? { get set }
    var m: String? { get set }
    var av: String? { get set }
    var l: String? { get set }
    var c: String? { get set }
    var dt: String? { get set }
    var v: String? { get set }
}

public final class MainServerHandler: Sendable {
    private static let callTimeout = 60.seconds

    public static let shared = MainServerHandler()

    private let urlConnection: URLConnection

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.urlConnection = urlConnection
    }

    private static let parserVersion = "1.7"
    private static let deviceType = "1"

    private let securityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"

        return formatter
    }()

    private let searchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private let tokenHelper = TokenHelper.shared

    struct PodcastSearchQuery: BaseRequest {
        var q: String?
        var dt: String?
        var device: String?
        var v: String?
        var m: String?
        var av: String?
        var l: String?
        var c: String?
    }

    private struct PodcastUuidSearchQuery: BaseRequest {
        var id: Int?
        var dt: String?
        var device: String?
        var v: String?
        var m: String?
        var av: String?
        var l: String?
        var c: String?
    }

    private struct ShareListRequest: BaseRequest {
        var dt: String?
        var device: String?
        var v: String?
        var m: String?
        var av: String?
        var l: String?
        var c: String?
    }

    private struct UploadOpmlRequest: BaseRequest {
        var urls: [String]?
        var pollUuids: [String]?
        var device: String?
        var m: String?
        var av: String?
        var l: String?
        var c: String?
        var dt: String?
        var v: String?

        public enum CodingKeys: String, CodingKey {
            case urls, pollUuids = "poll_uuids", device, m, av, l, c, dt, v
        }
    }

    public func sendOpmlChunk(feedUrls: [String] = [], pollUuids: [String] = [], completion: @escaping @Sendable (ImportOpmlResponse?) -> Void) {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            completion(ImportOpmlResponse.failedResponse())
            return
        }

        var baseRequest: BaseRequest = UploadOpmlRequest()
        addStandardParams(baseRequest: &baseRequest, uniqueId: uniqueId)

        var uploadRequest = baseRequest as! UploadOpmlRequest
        uploadRequest.urls = feedUrls
        uploadRequest.pollUuids = pollUuids

        let url = ServerHelper.asUrl(ServerConstants.Urls.main() + "import/opml")
        guard let request = ServerHelper.createJsonRequest(url: url, params: uploadRequest, timeout: MainServerHandler.callTimeout, cachePolicy: .reloadIgnoringCacheData) else {
            completion(ImportOpmlResponse.failedResponse())
            return
        }

        urlConnection.send(request: request) { data, _, error in
            guard let data, error == nil else {
                completion(ImportOpmlResponse.failedResponse())
                return
            }

            do {
                let refreshResponse = try JSONDecoder().decode(ImportOpmlResponse.self, from: data)
                completion(refreshResponse)
            } catch {
                completion(ImportOpmlResponse.failedResponse())
            }
        }
    }

    public func lookupShareLink(sharePath: String, completion: @escaping @Sendable (ShareListResponse?) -> Void) {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            completion(ShareListResponse.failedResponse())
            return
        }

        var shareLinkRequest: BaseRequest = ShareListRequest()
        addStandardParams(baseRequest: &shareLinkRequest, uniqueId: uniqueId)

        let url = ServerHelper.asUrl(ServerConstants.Urls.main() + sharePath)
        guard let request = ServerHelper.createJsonRequest(url: url, params: shareLinkRequest as! ShareListRequest, timeout: MainServerHandler.callTimeout, cachePolicy: .reloadIgnoringCacheData) else {
            completion(ShareListResponse.failedResponse())
            return
        }

        urlConnection.send(request: request) { data, _, error in
            guard let data, error == nil else {
                completion(ShareListResponse.failedResponse())
                return
            }

            do {
                let refreshResponse = try JSONDecoder().decode(ShareListResponse.self, from: data)
                completion(refreshResponse)
            } catch {
                completion(ShareListResponse.failedResponse())
            }
        }
    }

    public func refresh(podcasts: [Podcast], completion: @escaping @Sendable (PodcastRefreshResponse?) -> Void) {
        FileLog.shared.addMessage("Refresh - Started)")
        guard let request = createRefreshRequest(podcasts: podcasts) else {
            completion(PodcastRefreshResponse.failedResponse())
            return
        }

        tokenHelper.callSecureUrl(request: request) { response, data, error in
            let statusCode = response?.statusCode ?? 0

            guard statusCode == ServerConstants.HttpConstants.ok, let data else {
                if let error {
                    FileLog.shared.addMessage("Refresh failed: with error \(error.localizedDescription), status code \(statusCode)")
                } else {
                    FileLog.shared.addMessage("Refresh failed: response returned no data, status code \(statusCode)")
                }
                completion(PodcastRefreshResponse.failedResponse())
                return
            }
            FileLog.shared.addMessage("Decoding Refresh Response)")
            let refreshResponse = ServerHelper.decodeRefreshResponse(from: data)
            completion(refreshResponse)
        }
    }

    public func createRefreshRequest(podcasts: [Podcast]) -> URLRequest? {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            return nil
        }

        for podcast in podcasts { // ensure podcasts have up to date latest episode uuids
            ServerPodcastManager.shared.updateLatestEpisodeInfo(podcast: podcast, setDefaults: false)
        }

        let pushEnabled = ServerConfig.shared.syncDelegate?.isPushEnabled() ?? false

        var jsonRequest = jsonWithStandardParams(uniqueId: uniqueId)
        jsonRequest["push_sound"] = "11" // for legacy reasons, this is always the push sound we send, since it's no longer configurable
        jsonRequest["podcasts"] = podcasts.map(\.uuid).joined(separator: ",")
        jsonRequest["last_episodes"] = podcasts.map { $0.forceRefreshEpisodeFrom ?? $0.latestEpisodeUuid ?? "" }.joined(separator: ",")
        jsonRequest["push_messages_on"] = podcasts.map { (pushEnabled && $0.isPushEnabled) ? "1" : "0" }.joined()
        if let pushToken = ServerSettings.pushToken() {
            jsonRequest["push_token"] = pushToken
        }
        jsonRequest["push_on"] = pushEnabled ? "true" : "false"
        jsonRequest["push_environment"] = (ServerConfig.shared.syncDelegate?.production() ?? true) ? "production" : "sandbox"
        guard let data = try? JSONSerialization.data(withJSONObject: jsonRequest) else {
            FileLog.shared.addMessage("Failed to create refresh request")
            return nil
        }

        let url = ServerHelper.asUrl(ServerConstants.Urls.main() + "user/update")
        let request = ServerHelper.createJsonRequest(url: url, data: data, timeout: MainServerHandler.callTimeout, cachePolicy: .reloadIgnoringCacheData)

        return request
    }

    public func podcastSearch(searchTerm: String, completion: @escaping @Sendable (PodcastSearchResponse?) -> Void) {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            completion(PodcastSearchResponse.failedResponse())
            return
        }

        var baseQuery: BaseRequest = PodcastSearchQuery()
        addStandardParams(baseRequest: &baseQuery, uniqueId: uniqueId)

        var searchQuery = baseQuery as! PodcastSearchQuery
        searchQuery.q = searchTerm

        let searchOperation = PodcastSearchOperation(searchQuery: searchQuery, urlConnection: urlConnection, completionHandler: completion)
        searchQueue.addOperation(searchOperation)
    }

    func podcastSearchQuery(searchTerm: String) -> PodcastSearchQuery? {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            return nil
        }

        var baseQuery: BaseRequest = PodcastSearchQuery()
        addStandardParams(baseRequest: &baseQuery, uniqueId: uniqueId)

        var searchQuery = baseQuery as! PodcastSearchQuery
        searchQuery.q = searchTerm

        return searchQuery
    }

    public func refreshPodcastFeed(podcast: Podcast, completion: @escaping @Sendable (Bool) -> Void) {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            completion(false)

            return
        }

        var jsonRequest = jsonWithStandardParams(uniqueId: uniqueId)
        jsonRequest["podcast_uuid"] = podcast.uuid
        guard let data = try? JSONSerialization.data(withJSONObject: jsonRequest) else {
            FileLog.shared.addMessage("Failed to create refreshPodcastFeed request")
            completion(false)

            return
        }

        let url = ServerHelper.asUrl(ServerConstants.Urls.main() + "podcasts/refresh")
        let request = ServerHelper.createJsonRequest(url: url, data: data, timeout: MainServerHandler.callTimeout, cachePolicy: .reloadIgnoringCacheData)
        FileLog.shared.addMessage("Attempting to refresh podcast feed for \(podcast.uuid)")
        urlConnection.send(request: request) { _, response, error in
            guard let response = response as? HTTPURLResponse, response.statusCode == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("Feed refresh failed: \(error?.localizedDescription ?? "No error")")
                completion(false)

                return
            }

            FileLog.shared.addMessage("Server indicated podcast refresh was successful")
            completion(true)
        }
    }

    public func findPodcastByiTunesId(_ iTunesId: Int, completion: @escaping @Sendable (String?) -> Void) {
        guard let uniqueId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
            completion(nil)
            return
        }

        var baseQuery: BaseRequest = PodcastUuidSearchQuery()
        addStandardParams(baseRequest: &baseQuery, uniqueId: uniqueId)

        var searchQuery = baseQuery as! PodcastUuidSearchQuery
        searchQuery.id = iTunesId

        let url = ServerHelper.asUrl(ServerConstants.Urls.main() + "podcasts/show")
        guard let request = ServerHelper.createJsonRequest(url: url, params: searchQuery, timeout: MainServerHandler.callTimeout, cachePolicy: .useProtocolCachePolicy) else {
            completion(nil)
            return
        }

        urlConnection.send(request: request) { data, _, error in
            guard let data, error == nil else {
                completion(nil)
                return
            }

            do {
                let searchResponse = try JSONDecoder().decode(PodcastSearchResponse.self, from: data)
                completion(searchResponse.result?.podcast?.uuid)
            } catch {
                completion(nil)
            }
        }
    }

    public func updatePodcast(uuid: String, lastEpisodeUuid: String?) async throws -> Bool {
        guard var components = URLComponents(string: ServerConstants.Urls.main() + "api/v1/update_podcast") else { return false }
        components.queryItems = [URLQueryItem(name: "podcast_uuid", value: uuid)]
        if let lastEpisodeUuid { components.queryItems?.append(URLQueryItem(name: "last_episode_uuid", value: lastEpisodeUuid)) }
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        FileLog.shared.console("Update Podcast API start request \(url.absoluteString)")

        if Task.isCancelled {
            return false
        }

        let response = try await urlConnection.send(request: request)
        guard var urlResponse = response.1 as? HTTPURLResponse else {
            return false
        }

        FileLog.shared.console("Update Podcast API response status code \(urlResponse.statusCode)")

        for _ in 0 ..< 60 where urlResponse.statusCode == ServerConstants.HttpConstants.accepted {
            guard let location = urlResponse.value(forHTTPHeaderField: "Location") else {
                FileLog.shared.console("Update Podcast API response incorrect header")
                return false
            }
            FileLog.shared.console("Poll Podcast API with delay of 2 sec")
            try await Task.sleep(for: .seconds(2))
            if Task.isCancelled {
                return false
            }
            guard let newUrlResponse = try await pollUpdatePodcast(url: location) else {
                FileLog.shared.console("Poll Podcast API no response")
                return false
            }
            urlResponse = newUrlResponse
            FileLog.shared.console("Poll Podcast API new status code \(urlResponse.statusCode)")
        }

        return urlResponse.statusCode == ServerConstants.HttpConstants.ok
    }

    private func pollUpdatePodcast(url: String) async throws -> HTTPURLResponse? {
        guard let url = URL(string: url) else {
            FileLog.shared.console("Poll Podcast API anavailable url: \(url)")
            return nil
        }
        FileLog.shared.console("Poll Podcast API start fetching \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let response = try await urlConnection.send(request: request)
        return response.1 as? HTTPURLResponse
    }

    private func jsonWithStandardParams(uniqueId: String) -> [String: Any] {
        var json: [String: Any] = [:]
        let locale = Locale.current
        json["l"] = locale.language.languageCode?.identifier
        json["c"] = locale.region?.identifier

        json["m"] = DeviceUtil.systemVersion

        json["dt"] = MainServerHandler.deviceType
        json["v"] = MainServerHandler.parserVersion
        json["device"] = uniqueId
        json["av"] = ServerConfig.shared.syncDelegate?.appVersion()

        return json
    }

    private func addStandardParams(baseRequest: inout BaseRequest, uniqueId: String) {
        let locale = Locale.current
        baseRequest.l = locale.language.languageCode?.identifier
        baseRequest.c = locale.region?.identifier

        baseRequest.m = DeviceUtil.systemVersion

        baseRequest.dt = MainServerHandler.deviceType
        baseRequest.v = MainServerHandler.parserVersion
        baseRequest.device = uniqueId
        baseRequest.av = ServerConfig.shared.syncDelegate?.appVersion()
    }
}
