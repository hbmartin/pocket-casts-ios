import Foundation

/// Read and mutate podcast episodes, including playback, download and sync state.
///
/// `DataManager` is the production conformer; inject `any EpisodeRepository` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol EpisodeRepository: AnyObject {
    func findEpisode(uuid: String) -> Episode?
    func findBaseEpisode(uuid: String) -> BaseEpisode?
    func findEpisodeCount(podcastId: Int64) -> Int
    func findPlayedEpisodes(uuids: [String]) -> [String]
    func findMatchingEpisodes(uuids: [String]) -> [String]
    func findPlayedEpisodesCount(podcastId: Int64) async -> Int
    func markAllEpisodePlaybackHistorySynced()
    func downloadedEpisodeExists(uuid: String) -> Bool
    func findBaseEpisode(downloadTaskId: String) -> BaseEpisode?
    func findEpisodeWhere(customWhere: String, arguments: [Any]?) -> Episode?
    func findEpisodesWhereNotNull(propertyName: String) -> [BaseEpisode]
    func findEpisodesWhere(customWhere: String, arguments: [Any]?) -> [Episode]
    func findEpisodes(with term: String, podcastUUID: String) -> [Episode]
    func findPlaylistEpisodesWhere(query: String, arguments: [Any]?) -> [Episode]
    func findEpisodesAndPodcastsWhere(customWhere: String, listenedTo: Bool) -> [Episode]
    func findLatestEpisode(podcast: Podcast) -> Episode?
    func findLatestEpisodes(podcast: Podcast, limit: Int) -> [Episode]
    func unsyncedEpisodes(limit: Int) -> [Episode]
    func unsyncedUserEpisodes() -> [UserEpisode]
    func episodesWithListenHistory(limit: Int) -> [Episode]
    func dailyListeningTime(forLast days: Int) -> [String: Double]
    func failedDownloadedEpisodesCount() -> Int
    func oldestFailedEpisodeDownload() -> Date?
    func newestFailedEpisodeDownload() -> Date?
    func findDownloadedEpisodes() -> [BaseEpisode]
    func downloadedEpisodeCount() -> Int
    func save(episode: BaseEpisode)
    func bulkSave(episodes: [Episode])
    func bulkSetStarred(starred: Bool, episodes: [Episode], updateSyncStatus: Bool)
    func bulkUserFileDelete(baseEpisodes: [BaseEpisode])
    func saveIfNotModified(starred: Bool, episodeUuid: String) -> Bool
    func saveIfNotModified(archived: Bool, episodeUuid: String) -> Bool
    func saveIfNotModified(playingStatus: PlayingStatus, episodeUuid: String) -> Bool
    @discardableResult
    func saveIfNotModified(chapters: String, remoteModified: Int64, episodeUuid: String) -> Bool
    func saveEpisode(playedUpTo: Double, episode: BaseEpisode, updateSyncFlag: Bool)
    func saveEpisode(playingStatus: PlayingStatus, episode: BaseEpisode, updateSyncFlag: Bool)
    func saveEpisode(archived: Bool, episode: Episode, updateSyncFlag: Bool)
    func saveEpisode(excludeFromEpisodeLimit: Bool, episode: Episode)
    func saveEpisode(fileType: String, episode: Episode)
    func saveEpisode(contentType: String, episode: BaseEpisode)
    func saveEpisode(fileSize: Int64, episode: Episode)
    func saveBulkEpisodeSyncInfo(episodes: [EpisodeBasicData])
    func saveFrameCount(episode: BaseEpisode, frameCount: Int64)
    func findFrameCount(episode: BaseEpisode) -> Int64
    func saveEpisode(starred: Bool, starredModified: Int64?, episode: Episode, updateSyncFlag: Bool)
    func saveEpisode(duration: Double, episode: BaseEpisode, updateSyncFlag: Bool)
    func saveEpisode(playbackError: String?, episode: BaseEpisode)
    func saveEpisode(downloadStatus: DownloadStatus, episode: Episode)
    func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: BaseEpisode)
    func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: BaseEpisode)
    func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: BaseEpisode)
    func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: BaseEpisode)
    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: BaseEpisode)
    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, episode: BaseEpisode)
    func saveEpisode(downloadUrl: String, episodeUuid: String)
    func updateEpisodePlaybackInteractionDate(episode: BaseEpisode)
    func setEpisodePlaybackInteractionDate(interactionDate: Date, episodeUuid: String)
    func clearKeepEpisodeModified(episode: Episode)
    func clearEpisodePlaybackInteractionDate(episodeUuid: String)
    func clearEpisodePlaybackInteractionDatesBefore(date: Date)
    func clearAllEpisodePlayInteractions()
    func clearDownloadTaskId(episode: BaseEpisode)
    func bulkMarkAsPlayed(episodes: [Episode], updateSyncFlag: Bool)
    func bulkMarkAsPlayed(episodes: [UserEpisode], updateSyncFlag: Bool)
    func bulkMarkAsUnPlayed(baseEpisodes: [BaseEpisode], updateSyncFlag: Bool)
    func bulkArchive(episodes: [Episode], markAsNotDownloaded: Bool, markAsPlayed: Bool, updateSyncFlag: Bool)
    func bulkUnarchive(episodes: [Episode], updateSyncFlag: Bool)
    func markAllSynced(episodes: [Episode])
    func markAllSynced(episodeIDs: [String])
    func allEpisodesForPodcast(id: Int64) -> [Episode]
    func delete(episodeUuid: String)
    func deleteAllEpisodesInPodcast(podcastId: Int64)

    // MARK: Async variants

    // The returned models are mutable reference types: treat them as owned by
    // the awaiting task. The default implementations run the synchronous
    // requirement on a background queue; conformers can override with natively
    // async reads.
    func findEpisodeAsync(uuid: String) async -> Episode?
    func findBaseEpisodeAsync(uuid: String) async -> BaseEpisode?
    func findEpisodeCountAsync(podcastId: Int64) async -> Int
    func findEpisodesWhereAsync(customWhere: String, arguments: [Any]?) async -> [Episode]

    // Completes only after the write has landed, so callers can safely re-read
    // the saved record afterwards. The default implementation runs the
    // synchronous requirement on a background queue; conformers can override
    // with natively async writes.
    func saveAsync(episode: BaseEpisode) async
}

public extension EpisodeRepository {
    // Conveniences mirroring DataManager's default arguments, which protocol
    // requirements cannot express.
    func dailyListeningTime() -> [String: Double] {
        dailyListeningTime(forLast: 365)
    }

    func saveEpisode(starred: Bool, episode: Episode, updateSyncFlag: Bool) {
        saveEpisode(starred: starred, starredModified: nil, episode: episode, updateSyncFlag: updateSyncFlag)
    }

    func findEpisodeAsync(uuid: String) async -> Episode? {
        await runOffMainThread { self.findEpisode(uuid: uuid) }
    }

    func findBaseEpisodeAsync(uuid: String) async -> BaseEpisode? {
        await runOffMainThread { self.findBaseEpisode(uuid: uuid) }
    }

    func findEpisodeCountAsync(podcastId: Int64) async -> Int {
        await runOffMainThread { self.findEpisodeCount(podcastId: podcastId) }
    }

    func findEpisodesWhereAsync(customWhere: String, arguments: [Any]?) async -> [Episode] {
        await runOffMainThread { self.findEpisodesWhere(customWhere: customWhere, arguments: arguments) }
    }

    func saveAsync(episode: BaseEpisode) async {
        await runOffMainThread { self.save(episode: episode) }
    }
}

extension DataManager: EpisodeRepository {}
