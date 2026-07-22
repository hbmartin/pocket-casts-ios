import Foundation
import PocketCastsDataModel
import PocketCastsUtils

// Stored properties are formatters and OperationQueues,
// @unchecked Sendable: queues and formatters are configured at init and read-only afterwards.
public final class ServerPodcastManager: NSObject, @unchecked Sendable {
    private static let maxAutoDownloadSeperationTime = 12.hours

    public static let shared = ServerPodcastManager()

    let isoFormatter = ISO8601DateFormatter()

    let subscribeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    let importerQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private let urlConnection = URLConnection(handler: URLSession.shared)

    // MARK: - Podcast add functions

    /// This tries to add the podcast with UUID up to 7 times if the call fails first time.
    /// The retry mechanism is to be used in cases when the podcast was just added to server and the first call might fail because the server didn't have time to update.
    /// The call will be done a maximum of seven times, waiting for 2s, then 2s, 5s, 5s, 5s, 5s, 10s
    /// and then give up.
    /// - Parameters:
    ///   - podcastUuid: the uuid of the podcast to caache
    ///   - subscribe: if we should subscribe to the podcast after adding
    ///   - tries: the number of tries already done
    ///   - completion: the code to execute on completion
    public func addFromUuidWithRetries(podcastUuid: String, subscribe: Bool, autoDownloads: Int = 0, tries: Int = 0, completion: ((Bool) -> Void)?) {
        let completion = UncheckedSendable(completion)
        addFromUuid(podcastUuid: podcastUuid, subscribe: subscribe, autoDownloads: autoDownloads) { [weak self] success in
            guard let self else {
                return
            }

            if success {
                completion.value?(success)
                return
            }

            let nextTry = tries + 1
            if nextTry < 8 {
                DispatchQueue.global().asyncAfter(deadline: .now() + nextTry.pollWaitingTime) { [weak self] in
                    self?.addFromUuidWithRetries(podcastUuid: podcastUuid, subscribe: subscribe, autoDownloads: autoDownloads, tries: nextTry, completion: completion.value)
                }
                return
            }
            completion.value?(false)
        }
    }

    public func addFromUuid(podcastUuid: String, subscribe: Bool, autoDownloads: Int = 0, completion: ((Bool) -> Void)?) {
        let completion = UncheckedSendable(completion)
        CacheServerHandler.shared.loadPodcastInfo(podcastUuid: podcastUuid) { [weak self] podcastInfo, lastModified in
            if let podcastInfo {
                self?.addFromJson(lastModified: lastModified, podcastInfo: podcastInfo, subscribe: subscribe, autoDownloads: autoDownloads, completion: completion.value)
            } else {
                completion.value?(false)
            }
        }
    }

    public func addFromiTunesId(_ itunesId: Int, subscribe: Bool, autoDownloads: Int = 0, completion: ((Bool, String?) -> Void)?) {
        let completion = UncheckedSendable(completion)
        MainServerHandler.shared.findPodcastByiTunesId(itunesId) { [weak self] podcastUuid in
            guard let uuid = podcastUuid else {
                completion.value?(false, nil)
                return
            }

            self?.addFromUuid(podcastUuid: uuid, subscribe: subscribe, autoDownloads: autoDownloads, completion: { added in
                completion.value?(added, uuid)
            })
        }
    }

    @available(*, deprecated, message: "Use addFromJson(lastModified:podcastInfo:subscribe:autoDownloads:completion:) instead.")
    public func addFromJson(podcastUuid _: String, lastModified: String?, podcastInfo: [String: Any], subscribe: Bool, autoDownloads: Int, completion: ((Bool) -> Void)?) {
        addFromJson(lastModified: lastModified, podcastInfo: podcastInfo, subscribe: subscribe, autoDownloads: autoDownloads, completion: completion)
    }

    public func addFromJson(lastModified: String?, podcastInfo: [String: Any], subscribe: Bool, autoDownloads: Int, refreshSource: PodcastRefreshSource = .server, completion: ((Bool) -> Void)?) {
        // Handed wholesale to the subscribe queue; not touched by the caller afterwards.
        let podcastInfo = UncheckedSendable(podcastInfo)
        let completion = UncheckedSendable(completion)
        subscribeQueue.addOperation { [weak self] in
            guard let strongSelf = self else { return }

            let added = strongSelf.addPodcast(podcastInfo: podcastInfo.value, subscribe: subscribe, autoDownloads: autoDownloads, lastModified: lastModified, refreshSource: refreshSource)
            if subscribe, added { ServerConfig.shared.syncDelegate?.subscribedToPodcast() } // addFromUuid and addFromiTunesId end up here, so just need this one analytic
            completion.value?(added)
        }
    }

    /// Subscribes to (or adds) a feed parsed entirely on device — no Pocket Casts servers
    /// involved. Dedups by feed URL first so a feed already in the library (under either
    /// refresh regime) is subscribed in place instead of duplicated under a hash UUID.
    public func addLocalFeed(feedURL: String, subscribe: Bool, autoDownloads: Int = 0, completion: (@Sendable (Bool) -> Void)?) {
        if var existing = DataManager.sharedManager.findPodcast(feedURL: feedURL) {
            // The dedup match ignores userinfo, so freshly re-entered credentials
            // (e.g. an unsubscribe/resubscribe with `user:pass@`) would otherwise be
            // dropped here — keep them for the existing row's refreshes.
            if let credentials = LocalFeedURL.credentials(from: feedURL) {
                guard LocalFeedCredentials.save(user: credentials.user, password: credentials.password, podcastUuid: existing.uuid) else {
                    FileLog.shared.addMessage("ServerPodcastManager: failed to store re-entered credentials for \(LocalFeedURL.redactedForLogging(feedURL))")
                    completion?(false)
                    return
                }
            }
            if subscribe, !existing.isSubscribed() {
                existing.subscribed = 1
                // A signed-out resubscribe of a server-sourced row flips it to on-device
                // refresh (sticky); the identity matcher keeps its canonical catalog safe.
                if !SyncManager.isUserLoggedIn(), existing.feedRefreshSource == .server, !(existing.podcastUrl ?? "").isEmpty {
                    existing.feedRefreshSource = .localFeed
                }
                // resubscribes to a server-sourced row must sync; local rows never do
                existing.syncStatus = (existing.isLocalFeedSourced ? SyncStatus.synced : SyncStatus.notSynced).rawValue
                DataManager.sharedManager.save(podcast: existing)
                updateLatestEpisodeInfo(podcast: existing, setDefaults: true, autoDownloadLimit: autoDownloads)
                ServerConfig.shared.syncDelegate?.podcastAdded(podcastUuid: existing.uuid)
                refreshAfterSignedOutFlip(podcast: existing)
            }
            completion?(true)
            return
        }

        Task { [weak self] in
            guard let podcastInfo = await LocalPodcastSource().loadPodcastInfo(feedURL: feedURL) else {
                completion?(false)
                return
            }
            self?.addFromJson(lastModified: nil, podcastInfo: podcastInfo, subscribe: subscribe, autoDownloads: autoDownloads, refreshSource: .localFeed, completion: completion)
        }
    }

    public func addPodcastFromUpNextItem(_ upNextItem: UpNextItem, completion: ((Bool) -> Void)?) {
        if let existingPodcast = DataManager.sharedManager.findPodcast(uuid: upNextItem.podcastUuid, includeUnsubscribed: true) {
            // we have the podcast, but not the episode, so it's ok to just save it in
            addToDatabase(upNextItem: upNextItem, to: existingPodcast)
            completion?(true)

            return
        }

        // otherwise we don't have the podcast, try and get it
        addFromUuid(podcastUuid: upNextItem.podcastUuid, subscribe: false, autoDownloads: 0) { [weak self] added in
            if !added {
                completion?(false)
                return
            }

            guard let existingPodcast = DataManager.sharedManager.findPodcast(uuid: upNextItem.podcastUuid, includeUnsubscribed: true) else {
                completion?(false)
                return
            }

            // at this point we have the podcast, now we need the sync info for it if we're signed in
            if SyncManager.isUserLoggedIn() {
                guard let episodes = ApiServerHandler.shared.retrieveEpisodeTaskSynchronouusly(podcastUuid: upNextItem.podcastUuid) else { return }

                DataManager.sharedManager.saveBulkEpisodeSyncInfo(episodes: DataConverter.convert(syncInfoEpisodes: episodes))
            }

            self?.addToDatabase(upNextItem: upNextItem, to: existingPodcast)
            completion?(true)
        }
    }

    public func addMissingPodcast(episodeUuid: String, podcastUuid: String) {
        let url = ServerConstants.Urls.cache() + "mobile/podcast/findbyepisode/\(podcastUuid)/\(episodeUuid)"

        if let info = loadFrom(url: url), addPodcast(podcastInfo: info, subscribe: false, lastModified: nil) {
            // all good
        }
    }

    public func addMissingEpisode(episodeUuid: String, podcastUuid: String) -> Episode? {
        let url = ServerConstants.Urls.cache() + "mobile/podcast/findbyepisode/\(podcastUuid)/\(episodeUuid)"

        if let info = loadFrom(url: url) {
            return addEpisode(podcastInfo: info)
        }

        return nil
    }

    public func addMissingPodcastAndEpisode(episodeUuid: String, podcastUuid: String, shouldUpdateEpisode: Bool = false, completion: ((Episode?) -> ())? = nil) {
        let url = ServerConstants.Urls.cache() + "mobile/podcast/findbyepisode/\(podcastUuid)/\(episodeUuid)"

        guard let info = loadFrom(url: url) else {
            completion?(nil)
            return
        }

        let episode = addMissingEpisode(
            podcastInfo: info,
            podcastUuid: podcastUuid,
            shouldUpdateEpisode: shouldUpdateEpisode
        )
        completion?(episode)
    }

    private func addMissingEpisode(podcastInfo: [String: Any], podcastUuid: String, shouldUpdateEpisode: Bool) -> Episode? {
        guard ensurePodcastExists(podcastUuid: podcastUuid, podcastInfo: podcastInfo) else {
            return nil
        }

        var episode = addEpisode(podcastInfo: podcastInfo, shouldUpdate: shouldUpdateEpisode)

        if episode == nil {
            PodcastExistsHelper.shared.invalidate(uuid: podcastUuid)

            if ensurePodcastExists(podcastUuid: podcastUuid, podcastInfo: podcastInfo) {
                episode = addEpisode(podcastInfo: podcastInfo, shouldUpdate: shouldUpdateEpisode)
            }
        }

        return episode
    }

    private func ensurePodcastExists(podcastUuid: String, podcastInfo: [String: Any]) -> Bool {
        if PodcastExistsHelper.shared.exists(uuid: podcastUuid) {
            return true
        }

        return addPodcast(podcastInfo: podcastInfo, subscribe: false, lastModified: nil)
    }

    private func addToDatabase(upNextItem: UpNextItem, to podcast: Podcast) {
        // if we have this episode already, then we don't need to do anything here
        guard DataManager.sharedManager.findEpisode(uuid: upNextItem.episodeUuid) == nil else { return }

        var episode = Episode()
        episode.addedDate = Date()
        episode.podcastUuid = podcast.uuid
        episode.playingStatus = PlayingStatus.notPlayed.rawValue
        episode.episodeStatus = DownloadStatus.notDownloaded.rawValue
        episode.uuid = upNextItem.episodeUuid
        episode.title = upNextItem.title
        episode.downloadUrl = upNextItem.url
        episode.publishedDate = upNextItem.published
        episode.podcast_id = podcast.id

        DataManager.sharedManager.save(episode: episode)
    }

    private func addPodcast(podcastInfo: [String: Any], subscribe: Bool, autoDownloads: Int = 0, lastModified: String?, refreshSource: PodcastRefreshSource = .server) -> Bool {
        guard let podcastJson = podcastInfo["podcast"] as? [String: Any], let podcastUuid = podcastJson["uuid"] as? String else { return false }

        // check if we already have this podcast, and if we do treat it differently
        if var existingPodcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) {
            if existingPodcast.isSubscribed(), subscribe {
                PodcastExistsHelper.shared.markExists(uuid: podcastUuid)
                return true
            }

            if !existingPodcast.isSubscribed(), subscribe {
                // we have this podcast, just in a non-subscribed state, so subscribe to it
                existingPodcast.subscribed = 1
                existingPodcast.syncStatus = SyncStatus.notSynced.rawValue
                existingPodcast.autoDownloadSetting = (autoDownloads > 0 ? AutoDownloadSetting.latest : AutoDownloadSetting.off).rawValue

                // Signed-out subscribes must be self-sufficient: hand the row to the
                // on-device refresh pipeline (sticky — sign-in later doesn't move it
                // back; the episode-identity matcher keeps its server-canonical catalog
                // safe under local refresh). Rows without a feed URL stay on .server —
                // .localFeed without a URL never refreshes.
                if !SyncManager.isUserLoggedIn(),
                   existingPodcast.feedRefreshSource == .server,
                   !(existingPodcast.podcastUrl ?? "").isEmpty {
                    existingPodcast.feedRefreshSource = .localFeed
                }
                // Derive sync state from the final source, not only from whether this
                // invocation performed the source flip. Existing local-feed rows never sync.
                existingPodcast.syncStatus = (existingPodcast.isLocalFeedSourced ? SyncStatus.synced : SyncStatus.notSynced).rawValue
            }
            DataManager.sharedManager.save(podcast: existingPodcast)
            updateLatestEpisodeInfo(podcast: existingPodcast, setDefaults: true, autoDownloadLimit: autoDownloads)

            ServerConfig.shared.syncDelegate?.podcastAdded(podcastUuid: existingPodcast.uuid)
            PodcastExistsHelper.shared.markExists(uuid: podcastUuid)

            if existingPodcast.feedRefreshSource == .localFeed, subscribe {
                refreshAfterSignedOutFlip(podcast: existingPodcast)
            }

            return true
        }

        var podcast = Podcast.from(podcastJson: podcastJson, podcastInfo: podcastInfo, uuid: podcastUuid, subscribe: subscribe, autoDownloads: autoDownloads, lastModified: lastModified, isoFormatter: isoFormatter)

        // Signed-out subscribes flip to on-device refresh at subscribe time (a persisted,
        // deterministic decision — sticky across sign-in/out). The podcast keeps its
        // canonical UUID and server-seeded episodes; the episode-identity matcher makes
        // subsequent local refreshes safe.
        let feedUrlPresent = !((podcastJson["url"] as? String) ?? "").isEmpty
        let effectiveSource = Self.effectiveRefreshSource(
            requested: refreshSource,
            subscribe: subscribe,
            isLoggedIn: SyncManager.isUserLoggedIn(),
            feedUrlPresent: feedUrlPresent
        )

        podcast.feedRefreshSource = effectiveSource
        if effectiveSource == .localFeed {
            // never queued for account sync — the server either never issued this row a
            // sync identity (hash UUID) or will never be told about it (signed-out add)
            podcast.syncStatus = SyncStatus.synced.rawValue
        }

        podcast.sortOrder = highestSortOrderForHomeGrid() + 1

        // we don't accept podcasts with no episodes
        guard let episodesJson = podcastJson["episodes"] as? [[String: Any]] else { return false }

        // save the podcast so that it gets and ID
        // (value-type Podcast: capture the saved copy so podcast.id is populated for the episodes below)
        podcast = DataManager.sharedManager.save(podcast: podcast)

        var episodes = [Episode]()
        for episodeJson in episodesJson {
            let episode = Episode.from(episodeJson: episodeJson, podcastId: podcast.id, podcastUuid: podcast.uuid, isoFormatter: isoFormatter)
            episodes.append(episode)
        }
        DataManager.sharedManager.bulkSave(episodes: episodes)

        updateLatestEpisodeInfo(podcast: podcast, setDefaults: subscribe, autoDownloadLimit: autoDownloads)

        if subscribe { ServerConfig.shared.syncDelegate?.podcastAdded(podcastUuid: podcast.uuid) }
        PodcastExistsHelper.shared.markExists(uuid: podcastUuid)

        if effectiveSource == .localFeed, refreshSource == .server {
            // The row flipped to on-device refresh but its episodes were seeded from the
            // server cache JSON, so the local show-notes cache is empty for it. One
            // immediate local refresh closes that gap for every subscribe route at once.
            refreshAfterSignedOutFlip(podcast: podcast)
        }

        return true
    }

    /// One immediate on-device refresh after a subscribe leaves a row on `.localFeed`
    /// with a server-seeded catalog: parses the feed once so the offline
    /// show-notes/chapters/transcripts cache is populated (the display path reads it
    /// cache-only for `.localFeed` podcasts) and any episodes newer than the server
    /// cache land straight away.
    private func refreshAfterSignedOutFlip(podcast: Podcast) {
        RefreshManager.shared.refresh(podcast: podcast, from: "")
    }

    /// The subscribe-time refresh-source policy (pure; unit-tested). A signed-out
    /// subscribe of a server-sourced podcast lands on `.localFeed` so the library is
    /// fully self-sufficient without an account. Rows without a feed URL stay on
    /// `.server` — `.localFeed` without a URL never refreshes. Explicit `.localFeed`
    /// requests (the on-device ingest pipeline) are never overridden.
    static func effectiveRefreshSource(
        requested: PodcastRefreshSource,
        subscribe: Bool,
        isLoggedIn: Bool,
        feedUrlPresent: Bool
    ) -> PodcastRefreshSource {
        guard requested == .server, subscribe, !isLoggedIn, feedUrlPresent else { return requested }
        return .localFeed
    }

    private func addEpisode(podcastInfo: [String: Any], shouldUpdate: Bool = false) -> Episode? {
        guard let podcastJson = podcastInfo["podcast"] as? [String: Any],
              let podcastUuid = podcastJson["uuid"] as? String,
              let episodesJson = podcastJson["episodes"] as? [[String: Any]],
              let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true),
              let firstEpisode = episodesJson.first,
              let uuid = firstEpisode["uuid"] as? String else { return nil }

        if var episode = DataManager.sharedManager.findEpisode(uuid: uuid) {
            if shouldUpdate {
                let updatedEpisode = Episode.from(episodeJson: firstEpisode, podcastId: podcast.id, podcastUuid: podcast.uuid, isoFormatter: isoFormatter)

                // Refresh server-driven fields while preserving user state (playback, downloads, etc.)
                episode.title = updatedEpisode.title
                episode.downloadUrl = updatedEpisode.downloadUrl
                episode.fileType = updatedEpisode.fileType
                episode.sizeInBytes = updatedEpisode.sizeInBytes
                episode.duration = updatedEpisode.duration
                episode.publishedDate = updatedEpisode.publishedDate
                episode.episodeNumber = updatedEpisode.episodeNumber
                episode.seasonNumber = updatedEpisode.seasonNumber
                episode.episodeType = updatedEpisode.episodeType
                episode.hasGeneratedTranscript = updatedEpisode.hasGeneratedTranscript

                if episode.addedDate == nil {
                    episode.addedDate = updatedEpisode.addedDate
                }

                if episode.podcast_id == 0 {
                    episode.podcast_id = podcast.id
                }

                DataManager.sharedManager.save(episode: episode)
            }
            return episode
        }

        let episode = Episode.from(episodeJson: firstEpisode, podcastId: podcast.id, podcastUuid: podcast.uuid, isoFormatter: isoFormatter)

        DataManager.sharedManager.save(episode: episode)

        return episode
    }

    public func loadRecommendations(for podcastUUID: String, in region: String?) async throws -> PodcastCollection? {
        let components = URLComponents(string: ServerConstants.Urls.api())

        guard var components else {
            assertionFailure("[ServerPodcastManager] Recommendations API URL failed")
            throw URLError(.badURL)
        }

        components.path += "recommendations/podcast/\(podcastUUID)"

        if let region {
            components.queryItems = [
                URLQueryItem(name: "country", value: region)
            ]
        }

        guard let url = components.url else {
            assertionFailure("[ServerPodcastManager] Recommendations API construction failed")
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.setValue("application/json; charset=UTF8", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.addLocalizationHeaders()
        let (data, response) = try await urlConnection.send(request: request)

        if (response as? HTTPURLResponse)?.statusCode == ServerConstants.HttpConstants.notModified {
            return nil
        }

        guard let data else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(PodcastCollection.self, from: data)
    }

    private func loadFrom(url: String) -> [String: Any]? {
        let url = ServerHelper.asUrl(url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.setValue("application/json; charset=UTF8", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.addLocalizationHeaders()
        do {
            let (responseData, response) = try urlConnection.sendSynchronousRequest(with: request)
            guard let data = responseData else { return nil }

            if let response = response as? HTTPURLResponse, response.statusCode == ServerConstants.HttpConstants.notModified {
                return nil
            }
            if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                return jsonResponse
            }
        } catch {
            print("Failed to get from server \(error.localizedDescription)")
        }

        return nil
    }

    public func highestSortOrderForHomeGrid() -> Int32 {
        homeGridSortOrder(highest: true)
    }

    public func lowestSortOrderForHomeGrid() -> Int32 {
        homeGridSortOrder(highest: false)
    }

    public func highestSortOrderForFolder(_ folder: Folder) -> Int32 {
        let folderPodcasts = DataManager.sharedManager.allPodcastsInFolder(folder: folder)
        var highest: Int32 = 1

        for podcast in folderPodcasts {
            if podcast.sortOrder > highest { highest = podcast.sortOrder }
        }

        return highest
    }

    private func homeGridSortOrder(highest: Bool) -> Int32 {
        let gridPodcasts = DataManager.sharedManager.allPodcasts(includeUnsubscribed: false).filter { $0.folderUuid == nil }
        let allFolders = DataManager.sharedManager.allFolders()
        var value: Int32 = highest ? 1 : 0

        for podcast in gridPodcasts {
            if highest, podcast.sortOrder > value { value = podcast.sortOrder }
            else if !highest, podcast.sortOrder < value { value = podcast.sortOrder }
        }

        for folder in allFolders {
            if highest, folder.sortOrder > value { value = folder.sortOrder }
            else if !highest, folder.sortOrder < value { value = folder.sortOrder }
        }

        return value
    }
}
