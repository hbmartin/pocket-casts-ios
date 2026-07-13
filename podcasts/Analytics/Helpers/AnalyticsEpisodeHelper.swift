import Dependencies
import Foundation
import PocketCastsDataModel
import Synchronization

// @unchecked Sendable: restates AnalyticsCoordinator's conformance, as Swift requires
// of subclasses; own state is guarded by a Mutex / ThreadSafeDictionary.
nonisolated class AnalyticsEpisodeHelper: AnalyticsCoordinator, @unchecked Sendable {
    static let shared = AnalyticsEpisodeHelper()

    @Dependency(\.episodeRepository) private var episodeRepository: any EpisodeRepository
    // Internally track the episode UUIDs that the user is downloading.
    private let episodeDownloadQueue = Mutex<Set<String>>([])
    // Keep track of where a download was initiated so completion/failure logs use the same source
    private let episodeDownloadSources = ThreadSafeDictionary<String, AnalyticsSource>()
    // Held for the helper's whole (process-long) lifetime; set once in init.
    private var episodeDownloadedToken: NotificationCenter.ObservationToken?

    override init() {
        super.init()
        addNotificationObservers()
    }

    func setup() {
        // Empty method just to ensure that sigleton is initialized
    }

    // MARK: - Star

    func star(episode: BaseEpisode) {
        episodeEvent(.episodeStarred, episode: episode)
    }

    func bulkStar(count: Int) {
        bulkEvent(.episodeBulkStarred, count: count)
    }

    func unstar(episode: BaseEpisode) {
        episodeEvent(.episodeUnstarred, episode: episode)
    }

    func bulkUnstar(count: Int) {
        bulkEvent(.episodeBulkUnstarred, count: count)
    }


    // MARK: - Download

    func downloadCancelled(episodeUUID: String) {
        clearDownloadSource(for: episodeUUID)
        episodeEvent(.episodeDownloadCancelled, uuid: episodeUUID)
    }

    func downloaded(episodeUUID: String) {
        let source = cacheDownloadSource(for: episodeUUID)
        episodeDownloadQueue.withLock { _ = $0.insert(episodeUUID) }
        currentSource = source
        episodeEvent(.episodeDownloadQueued, uuid: episodeUUID)
    }

    func downloadFinished(episodeUUID: String) {
        let source = consumeDownloadSource(for: episodeUUID)
        if let source {
            currentSource = source
        }
        episodeEvent(.episodeDownloadFinished, uuid: episodeUUID)
    }

    func downloadFailed(episodeUUID: String,
                        podcastUUID: String,
                        extraProperties: [String: Any]) {
        let source = consumeDownloadSource(for: episodeUUID)
        if let source {
            currentSource = source
        }
        track(.episodeDownloadFailed, properties: ["episode_uuid": episodeUUID,
                                                   "podcast_uuid": podcastUUID,
                                                  ].merging(extraProperties, uniquingKeysWith: { current, _ in return current }))
    }

    func bulkDownloadEpisodes(episodes: [BaseEpisode]) {
        let uuids = episodes.map { $0.uuid }
        let source = cacheDownloadSource(for: uuids)
        episodeDownloadQueue.withLock { $0.formUnion(uuids) }
        currentSource = source
        bulkEvent(.episodeBulkDownloadQueued, count: episodes.count)
    }

    func downloadDeleted(episode: BaseEpisode) {
        episodeEvent(.episodeDownloadDeleted, episode: episode)
    }

    func bulkDeleteDownloadedEpisodes(count: Int) {
        bulkEvent(.episodeBulkDownloadDeleted, count: count)
    }

    // MARK: - Played

    func markAsPlayed(episode: BaseEpisode) {
        episodeEvent(.episodeMarkedAsPlayed, episode: episode)
    }

    func bulkMarkAsPlayed(count: Int) {
        bulkEvent(.episodeBulkMarkedAsPlayed, count: count)
    }

    func markAsUnplayed(episode: BaseEpisode) {
        episodeEvent(.episodeMarkedAsUnplayed, episode: episode)
    }

    func bulkMarkAsUnplayed(count: Int) {
        bulkEvent(.episodeBulkMarkedAsUnplayed, count: count)
    }

    func bulkRemoveFromListeningHistory(count: Int) {
        bulkEvent(.episodeRemovedListeningHistory, count: count)
    }

    // MARK: - Archive

    func archiveEpisode(_ episode: BaseEpisode) {
        episodeEvent(.episodeArchived, episode: episode)
    }

    func bulkArchiveEpisodes(count: Int) {
        bulkEvent(.episodeBulkArchived, count: count)
    }

    func unarchiveEpisode(_ episode: BaseEpisode) {
        episodeEvent(.episodeUnarchived, episode: episode)
    }

    func bulkUnarchiveEpisodes(count: Int) {
        bulkEvent(.episodeBulkUnarchived, count: count)
    }

    // MARK: - Up Next

    func episodeAddedToUpNext(episode: BaseEpisode, toTop: Bool) {
        track(.episodeAddedToUpNext, properties: ["episode_uuid": episode.uuid, "podcast_uuid": episode.parentIdentifier(), "to_top": toTop])
    }

    func bulkAddToUpNext(count: Int, toTop: Bool) {
        track(.episodeBulkAddToUpNext, properties: ["episode_count": count, "to_top": toTop])
    }

    func episodeRemovedFromUpNext(episode: BaseEpisode) {
        episodeEvent(.episodeRemovedFromUpNext, episode: episode)
    }
}

nonisolated private extension AnalyticsEpisodeHelper {
    func cacheDownloadSource(for episodeUUID: String) -> AnalyticsSource {
        let source = currentAnalyticsSource
        episodeDownloadSources[episodeUUID] = source
        return source
    }

    func cacheDownloadSource(for episodeUUIDs: [String]) -> AnalyticsSource {
        let source = currentAnalyticsSource
        episodeUUIDs.forEach { episodeDownloadSources[$0] = source }
        return source
    }

    func consumeDownloadSource(for episodeUUID: String) -> AnalyticsSource? {
        let source = episodeDownloadSources[episodeUUID]
        episodeDownloadSources[episodeUUID] = nil
        return source
    }

    func clearDownloadSource(for episodeUUID: String) {
        episodeDownloadSources.removeValue(forKey: episodeUUID)
    }

    func episodeEvent(_ event: AnalyticsEvent, episode: BaseEpisode? = nil, uuid: String? = nil) {
        let episodeUUID: String
        if let episode {
            episodeUUID = episode.uuid
        } else if let uuid {
            episodeUUID = uuid
        } else {
            episodeUUID = "unknown"
        }

        track(event, properties: ["episode_uuid": episodeUUID])
    }

    func bulkEvent(_ event: AnalyticsEvent, count: Int) {
        track(event, properties: ["episode_count": count])
    }
}

nonisolated private extension AnalyticsEpisodeHelper {
    func addNotificationObservers() {
        episodeDownloadedToken = NotificationCenter.default.addObserver(for: EpisodeDownloaded.self) { [weak self] message in
            // Verify the UUID is one that we're tracking
            guard let self, let uuid = message.uuid, self.episodeDownloadQueue.withLock({ $0.contains(uuid) }) else {
                return
            }

            // Verify that the file has finished downloading
            guard
                let episode = self.episodeRepository.findEpisode(uuid: uuid),
                let status = DownloadStatus(rawValue: episode.episodeStatus),
                status == .downloaded
            else {
                return
            }

            self.episodeDownloadQueue.withLock { _ = $0.remove(uuid) }
            self.downloadFinished(episodeUUID: uuid)
        }
    }
}
