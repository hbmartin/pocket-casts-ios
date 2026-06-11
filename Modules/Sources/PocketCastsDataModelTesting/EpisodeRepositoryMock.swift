import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `EpisodeRepository`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
public final class EpisodeRepositoryMock: RepositoryMock, EpisodeRepository {
    public func findEpisode(uuid: String) -> Episode? {
        record("findEpisode(uuid:)")
        return stubs["findEpisode(uuid:)"] as? Episode
    }

    public func findBaseEpisode(uuid: String) -> BaseEpisode? {
        record("findBaseEpisode(uuid:)")
        return stubs["findBaseEpisode(uuid:)"] as? BaseEpisode
    }

    public func findEpisodeCount(podcastId: Int64) -> Int {
        record("findEpisodeCount(podcastId:)")
        return stubs["findEpisodeCount(podcastId:)"] as? Int ?? 0
    }

    public func findPlayedEpisodes(uuids: [String]) -> [String] {
        record("findPlayedEpisodes(uuids:)")
        return stubs["findPlayedEpisodes(uuids:)"] as? [String] ?? []
    }

    public func findMatchingEpisodes(uuids: [String]) -> [String] {
        record("findMatchingEpisodes(uuids:)")
        return stubs["findMatchingEpisodes(uuids:)"] as? [String] ?? []
    }

    public func findPlayedEpisodesCount(podcastId: Int64) async -> Int {
        record("findPlayedEpisodesCount(podcastId:)")
        return stubs["findPlayedEpisodesCount(podcastId:)"] as? Int ?? 0
    }

    public func markAllEpisodePlaybackHistorySynced() {
        record("markAllEpisodePlaybackHistorySynced()")
    }

    public func downloadedEpisodeExists(uuid: String) -> Bool {
        record("downloadedEpisodeExists(uuid:)")
        return stubs["downloadedEpisodeExists(uuid:)"] as? Bool ?? false
    }

    public func findBaseEpisode(downloadTaskId: String) -> BaseEpisode? {
        record("findBaseEpisode(downloadTaskId:)")
        return stubs["findBaseEpisode(downloadTaskId:)"] as? BaseEpisode
    }

    public func findEpisodeWhere(customWhere: String, arguments: [Any]?) -> Episode? {
        record("findEpisodeWhere(customWhere:arguments:)")
        return stubs["findEpisodeWhere(customWhere:arguments:)"] as? Episode
    }

    public func findEpisodesWhereNotNull(propertyName: String) -> [BaseEpisode] {
        record("findEpisodesWhereNotNull(propertyName:)")
        return stubs["findEpisodesWhereNotNull(propertyName:)"] as? [BaseEpisode] ?? []
    }

    public func findEpisodesWhere(customWhere: String, arguments: [Any]?) -> [Episode] {
        record("findEpisodesWhere(customWhere:arguments:)")
        return stubs["findEpisodesWhere(customWhere:arguments:)"] as? [Episode] ?? []
    }

    public func findEpisodes(with term: String, podcastUUID: String) -> [Episode] {
        record("findEpisodes(with:podcastUUID:)")
        return stubs["findEpisodes(with:podcastUUID:)"] as? [Episode] ?? []
    }

    public func findPlaylistEpisodesWhere(query: String, arguments: [Any]?) -> [Episode] {
        record("findPlaylistEpisodesWhere(query:arguments:)")
        return stubs["findPlaylistEpisodesWhere(query:arguments:)"] as? [Episode] ?? []
    }

    public func findEpisodesAndPodcastsWhere(customWhere: String, listenedTo: Bool) -> [Episode] {
        record("findEpisodesAndPodcastsWhere(customWhere:listenedTo:)")
        return stubs["findEpisodesAndPodcastsWhere(customWhere:listenedTo:)"] as? [Episode] ?? []
    }

    public func findLatestEpisode(podcast: Podcast) -> Episode? {
        record("findLatestEpisode(podcast:)")
        return stubs["findLatestEpisode(podcast:)"] as? Episode
    }

    public func findLatestEpisodes(podcast: Podcast, limit: Int) -> [Episode] {
        record("findLatestEpisodes(podcast:limit:)")
        return stubs["findLatestEpisodes(podcast:limit:)"] as? [Episode] ?? []
    }

    public func unsyncedEpisodes(limit: Int) -> [Episode] {
        record("unsyncedEpisodes(limit:)")
        return stubs["unsyncedEpisodes(limit:)"] as? [Episode] ?? []
    }

    public func unsyncedUserEpisodes() -> [UserEpisode] {
        record("unsyncedUserEpisodes()")
        return stubs["unsyncedUserEpisodes()"] as? [UserEpisode] ?? []
    }

    public func episodesWithListenHistory(limit: Int) -> [Episode] {
        record("episodesWithListenHistory(limit:)")
        return stubs["episodesWithListenHistory(limit:)"] as? [Episode] ?? []
    }

    public func dailyListeningTime(forLast days: Int) -> [String: Double] {
        record("dailyListeningTime(forLast:)")
        return stubs["dailyListeningTime(forLast:)"] as? [String: Double] ?? [:]
    }

    public func failedDownloadedEpisodesCount() -> Int {
        record("failedDownloadedEpisodesCount()")
        return stubs["failedDownloadedEpisodesCount()"] as? Int ?? 0
    }

    public func oldestFailedEpisodeDownload() -> Date? {
        record("oldestFailedEpisodeDownload()")
        return stubs["oldestFailedEpisodeDownload()"] as? Date
    }

    public func newestFailedEpisodeDownload() -> Date? {
        record("newestFailedEpisodeDownload()")
        return stubs["newestFailedEpisodeDownload()"] as? Date
    }

    public func findDownloadedEpisodes() -> [BaseEpisode] {
        record("findDownloadedEpisodes()")
        return stubs["findDownloadedEpisodes()"] as? [BaseEpisode] ?? []
    }

    public func downloadedEpisodeCount() -> Int {
        record("downloadedEpisodeCount()")
        return stubs["downloadedEpisodeCount()"] as? Int ?? 0
    }

    public func save(episode: BaseEpisode) {
        record("save(episode:)")
    }

    public func bulkSave(episodes: [Episode]) {
        record("bulkSave(episodes:)")
    }

    public func bulkSetStarred(starred: Bool, episodes: [Episode], updateSyncStatus: Bool) {
        record("bulkSetStarred(starred:episodes:updateSyncStatus:)")
    }

    public func bulkUserFileDelete(baseEpisodes: [BaseEpisode]) {
        record("bulkUserFileDelete(baseEpisodes:)")
    }

    public func saveIfNotModified(starred: Bool, episodeUuid: String) -> Bool {
        record("saveIfNotModified(starred:episodeUuid:)")
        return stubs["saveIfNotModified(starred:episodeUuid:)"] as? Bool ?? false
    }

    public func saveIfNotModified(archived: Bool, episodeUuid: String) -> Bool {
        record("saveIfNotModified(archived:episodeUuid:)")
        return stubs["saveIfNotModified(archived:episodeUuid:)"] as? Bool ?? false
    }

    public func saveIfNotModified(playingStatus: PlayingStatus, episodeUuid: String) -> Bool {
        record("saveIfNotModified(playingStatus:episodeUuid:)")
        return stubs["saveIfNotModified(playingStatus:episodeUuid:)"] as? Bool ?? false
    }

    @discardableResult
    public func saveIfNotModified(chapters: String, remoteModified: Int64, episodeUuid: String) -> Bool {
        record("saveIfNotModified(chapters:remoteModified:episodeUuid:)")
        return stubs["saveIfNotModified(chapters:remoteModified:episodeUuid:)"] as? Bool ?? false
    }

    public func saveEpisode(playedUpTo: Double, episode: BaseEpisode, updateSyncFlag: Bool) {
        record("saveEpisode(playedUpTo:episode:updateSyncFlag:)")
    }

    public func saveEpisode(playingStatus: PlayingStatus, episode: BaseEpisode, updateSyncFlag: Bool) {
        record("saveEpisode(playingStatus:episode:updateSyncFlag:)")
    }

    public func saveEpisode(archived: Bool, episode: Episode, updateSyncFlag: Bool) {
        record("saveEpisode(archived:episode:updateSyncFlag:)")
    }

    public func saveEpisode(excludeFromEpisodeLimit: Bool, episode: Episode) {
        record("saveEpisode(excludeFromEpisodeLimit:episode:)")
    }

    public func saveEpisode(fileType: String, episode: Episode) {
        record("saveEpisode(fileType:episode:)")
    }

    public func saveEpisode(contentType: String, episode: BaseEpisode) {
        record("saveEpisode(contentType:episode:)")
    }

    public func saveEpisode(fileSize: Int64, episode: Episode) {
        record("saveEpisode(fileSize:episode:)")
    }

    public func saveBulkEpisodeSyncInfo(episodes: [EpisodeBasicData]) {
        record("saveBulkEpisodeSyncInfo(episodes:)")
    }

    public func saveFrameCount(episode: BaseEpisode, frameCount: Int64) {
        record("saveFrameCount(episode:frameCount:)")
    }

    public func findFrameCount(episode: BaseEpisode) -> Int64 {
        record("findFrameCount(episode:)")
        return stubs["findFrameCount(episode:)"] as? Int64 ?? 0
    }

    public func saveEpisode(starred: Bool, starredModified: Int64?, episode: Episode, updateSyncFlag: Bool) {
        record("saveEpisode(starred:starredModified:episode:updateSyncFlag:)")
    }

    public func saveEpisode(duration: Double, episode: BaseEpisode, updateSyncFlag: Bool) {
        record("saveEpisode(duration:episode:updateSyncFlag:)")
    }

    public func saveEpisode(playbackError: String?, episode: BaseEpisode) {
        record("saveEpisode(playbackError:episode:)")
    }

    public func saveEpisode(downloadStatus: DownloadStatus, episode: Episode) {
        record("saveEpisode(downloadStatus:episode:)")
    }

    public func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: BaseEpisode) {
        record("saveEpisode(downloadStatus:lastDownloadAttemptDate:autoDownloadStatus:episode:)")
    }

    public func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: BaseEpisode) {
        record("saveEpisode(downloadStatus:downloadError:downloadTaskId:episode:)")
    }

    public func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: BaseEpisode) {
        record("saveEpisode(autoDownloadStatus:episode:)")
    }

    public func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: BaseEpisode) {
        record("saveEpisode(downloadStatus:downloadTaskId:episode:)")
    }

    public func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: BaseEpisode) {
        record("saveEpisode(downloadStatus:sizeInBytes:downloadTaskId:episode:)")
    }

    public func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, episode: BaseEpisode) {
        record("saveEpisode(downloadStatus:sizeInBytes:episode:)")
    }

    public func saveEpisode(downloadUrl: String, episodeUuid: String) {
        record("saveEpisode(downloadUrl:episodeUuid:)")
    }

    public func updateEpisodePlaybackInteractionDate(episode: BaseEpisode) {
        record("updateEpisodePlaybackInteractionDate(episode:)")
    }

    public func setEpisodePlaybackInteractionDate(interactionDate: Date, episodeUuid: String) {
        record("setEpisodePlaybackInteractionDate(interactionDate:episodeUuid:)")
    }

    public func clearKeepEpisodeModified(episode: Episode) {
        record("clearKeepEpisodeModified(episode:)")
    }

    public func clearEpisodePlaybackInteractionDate(episodeUuid: String) {
        record("clearEpisodePlaybackInteractionDate(episodeUuid:)")
    }

    public func clearEpisodePlaybackInteractionDatesBefore(date: Date) {
        record("clearEpisodePlaybackInteractionDatesBefore(date:)")
    }

    public func clearAllEpisodePlayInteractions() {
        record("clearAllEpisodePlayInteractions()")
    }

    public func clearDownloadTaskId(episode: BaseEpisode) {
        record("clearDownloadTaskId(episode:)")
    }

    public func bulkMarkAsPlayed(episodes: [Episode], updateSyncFlag: Bool) {
        record("bulkMarkAsPlayed(episodes:[Episode]:updateSyncFlag:)")
    }

    public func bulkMarkAsPlayed(episodes: [UserEpisode], updateSyncFlag: Bool) {
        record("bulkMarkAsPlayed(episodes:[UserEpisode]:updateSyncFlag:)")
    }

    public func bulkMarkAsUnPlayed(baseEpisodes: [BaseEpisode], updateSyncFlag: Bool) {
        record("bulkMarkAsUnPlayed(baseEpisodes:updateSyncFlag:)")
    }

    public func bulkArchive(episodes: [Episode], markAsNotDownloaded: Bool, markAsPlayed: Bool, updateSyncFlag: Bool) {
        record("bulkArchive(episodes:markAsNotDownloaded:markAsPlayed:updateSyncFlag:)")
    }

    public func bulkUnarchive(episodes: [Episode], updateSyncFlag: Bool) {
        record("bulkUnarchive(episodes:updateSyncFlag:)")
    }

    public func markAllSynced(episodes: [Episode]) {
        record("markAllSynced(episodes:)")
    }

    public func markAllSynced(episodeIDs: [String]) {
        record("markAllSynced(episodeIDs:)")
    }

    public func allEpisodesForPodcast(id: Int64) -> [Episode] {
        record("allEpisodesForPodcast(id:)")
        return stubs["allEpisodesForPodcast(id:)"] as? [Episode] ?? []
    }

    public func delete(episodeUuid: String) {
        record("delete(episodeUuid:)")
    }

    public func deleteAllEpisodesInPodcast(podcastId: Int64) {
        record("deleteAllEpisodesInPodcast(podcastId:)")
    }
}
