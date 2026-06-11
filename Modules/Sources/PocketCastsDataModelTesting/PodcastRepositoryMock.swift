import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `PodcastRepository`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
public final class PodcastRepositoryMock: RepositoryMock, PodcastRepository {
    public func allPodcasts(includeUnsubscribed: Bool, reloadFromDatabase: Bool) -> [Podcast] {
        record("allPodcasts(includeUnsubscribed:reloadFromDatabase:)")
        return stubs["allPodcasts(includeUnsubscribed:reloadFromDatabase:)"] as? [Podcast] ?? []
    }

    public func searchPodcasts(term: String) -> [Podcast] {
        record("searchPodcasts(term:)")
        return stubs["searchPodcasts(term:)"] as? [Podcast] ?? []
    }

    public func allPodcastsOrderedByTitle(reloadFromDatabase: Bool) -> [Podcast] {
        record("allPodcastsOrderedByTitle(reloadFromDatabase:)")
        return stubs["allPodcastsOrderedByTitle(reloadFromDatabase:)"] as? [Podcast] ?? []
    }

    public func allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: Bool) -> [Podcast] {
        record("allPodcastsOrderedByNewestEpisodes(reloadFromDatabase:)")
        return stubs["allPodcastsOrderedByNewestEpisodes(reloadFromDatabase:)"] as? [Podcast] ?? []
    }

    public func allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: Bool) -> [Podcast] {
        record("allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase:)")
        return stubs["allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase:)"] as? [Podcast] ?? []
    }

    public func allPodcastsOrderedByAddedDate(reloadFromDatabase: Bool) -> [Podcast] {
        record("allPodcastsOrderedByAddedDate(reloadFromDatabase:)")
        return stubs["allPodcastsOrderedByAddedDate(reloadFromDatabase:)"] as? [Podcast] ?? []
    }

    public func findPodcast(uuid: String, includeUnsubscribed: Bool) -> Podcast? {
        record("findPodcast(uuid:includeUnsubscribed:)")
        return stubs["findPodcast(uuid:includeUnsubscribed:)"] as? Podcast
    }

    public func allUnsubscribedPodcastUuids() -> [String] {
        record("allUnsubscribedPodcastUuids()")
        return stubs["allUnsubscribedPodcastUuids()"] as? [String] ?? []
    }

    public func allUnsubscribedPodcasts() -> [Podcast] {
        record("allUnsubscribedPodcasts()")
        return stubs["allUnsubscribedPodcasts()"] as? [Podcast] ?? []
    }

    public func allPaidPodcasts() -> [Podcast] {
        record("allPaidPodcasts()")
        return stubs["allPaidPodcasts()"] as? [Podcast] ?? []
    }

    public func allOverrideGlobalArchivePodcasts() -> [Podcast] {
        record("allOverrideGlobalArchivePodcasts()")
        return stubs["allOverrideGlobalArchivePodcasts()"] as? [Podcast] ?? []
    }

    public func podcastCount() -> Int {
        record("podcastCount()")
        return stubs["podcastCount()"] as? Int ?? 0
    }

    public func randomPodcasts() -> [Podcast] {
        record("randomPodcasts()")
        return stubs["randomPodcasts()"] as? [Podcast] ?? []
    }

    public func podcastUnfinishedCounts() -> [String: Int32] {
        record("podcastUnfinishedCounts()")
        return stubs["podcastUnfinishedCounts()"] as? [String: Int32] ?? [:]
    }

    public func markAllPodcastsSynced() {
        record("markAllPodcastsSynced()")
    }

    public func markAllPodcastsUnsynced() {
        record("markAllPodcastsUnsynced()")
    }

    public func markAllPodcastsUnsyncedWhereLastSyncAtNot(_ lastSyncAt: String) {
        record("markAllPodcastsUnsyncedWhereLastSyncAtNot(_:)")
    }

    public func setPushForAllPodcasts(pushEnabled: Bool) {
        record("setPushForAllPodcasts(pushEnabled:)")
    }

    public func saveAutoAddToUpNextForAllPodcasts(autoAddToUpNext: Int32) {
        record("saveAutoAddToUpNextForAllPodcasts(autoAddToUpNext:)")
    }

    public func updateAutoAddToUpNext(to value: AutoAddToUpNextSetting, for podcasts: [Podcast]) {
        record("updateAutoAddToUpNext(to:for:)")
    }

    public func setDownloadSettingForAllPodcasts(setting: AutoDownloadSetting) {
        record("setDownloadSettingForAllPodcasts(setting:)")
    }

    public func allUnsyncedPodcasts() -> [Podcast] {
        record("allUnsyncedPodcasts()")
        return stubs["allUnsyncedPodcasts()"] as? [Podcast] ?? []
    }

    public func delete(podcast: Podcast) {
        record("delete(podcast:)")
    }

    public func save(podcast: Podcast) {
        record("save(podcast:)")
    }

    public func savePushSetting(podcast: Podcast, pushEnabled: Bool) {
        record("savePushSetting(podcast:pushEnabled:)")
    }

    public func savePushSetting(podcastUuid: String, pushEnabled: Bool) {
        record("savePushSetting(podcastUuid:pushEnabled:)")
    }

    public func saveAutoAddToUpNext(podcastUuid: String, autoAddToUpNext: Int32) {
        record("saveAutoAddToUpNext(podcastUuid:autoAddToUpNext:)")
    }

    public func savePodcastDownloadSetting(_ setting: AutoDownloadSetting, podcastUuid: String) {
        record("savePodcastDownloadSetting(_:podcastUuid:)")
    }

    public func saveAutoArchiveLimit(podcast: Podcast, limit: Int32) {
        record("saveAutoArchiveLimit(podcast:limit:)")
    }

    public func saveSortOrders(podcasts: [Podcast]) {
        record("saveSortOrders(podcasts:)")
    }

    public func markAllUnarchivedForPodcast(id: Int64) {
        record("markAllUnarchivedForPodcast(id:)")
    }

    public func updateAllPodcastGrouping(to grouping: PodcastGrouping) {
        record("updateAllPodcastGrouping(to:)")
    }

    public func updateAllShowArchived(to showArchived: Bool) {
        record("updateAllShowArchived(to:)")
    }

    public func setPodcastImageVersion(podcastUuid: String, version: Int) {
        record("setPodcastImageVersion(podcastUuid:version:)")
    }

    public func setAllPodcastImageVersions(to version: Int) {
        record("setAllPodcastImageVersions(to:)")
    }

    public func bulkSetFolderUuid(folderUuid: String, podcastUuids: [String]) {
        record("bulkSetFolderUuid(folderUuid:podcastUuids:)")
    }

    public func updatePodcastFolder(podcastUuid: String, to folderUuid: String?, sortOrder: Int32) {
        record("updatePodcastFolder(podcastUuid:to:sortOrder:)")
    }

    public func setPushDefaultForNewPodcast(_ podcast: Podcast) {
        record("setPushDefaultForNewPodcast(_:)")
    }

    public func pushEnabledPodcastsCount() -> Int {
        record("pushEnabledPodcastsCount()")
        return stubs["pushEnabledPodcastsCount()"] as? Int ?? 0
    }
}
