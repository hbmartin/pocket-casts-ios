import Foundation

/// Read and mutate podcasts and podcast-level settings, including push notification preferences.
///
/// `DataManager` is the production conformer; inject `any PodcastRepository` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol PodcastRepository: AnyObject, Sendable {
    func allPodcasts(includeUnsubscribed: Bool, reloadFromDatabase: Bool) -> [Podcast]
    func searchPodcasts(term: String) -> [Podcast]
    func allPodcastsOrderedByTitle(reloadFromDatabase: Bool) -> [Podcast]
    func allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: Bool) -> [Podcast]
    func allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: Bool) -> [Podcast]
    func allPodcastsOrderedByAddedDate(reloadFromDatabase: Bool) -> [Podcast]
    func findPodcast(uuid: String, includeUnsubscribed: Bool) -> Podcast?
    func allUnsubscribedPodcastUuids() -> [String]
    func allUnsubscribedPodcasts() -> [Podcast]
    func allPaidPodcasts() -> [Podcast]
    func allOverrideGlobalArchivePodcasts() -> [Podcast]
    func podcastCount() -> Int
    func randomPodcasts() -> [Podcast]
    func podcastUnfinishedCounts() -> [String: Int32]
    func markAllPodcastsSynced()
    func markAllPodcastsUnsynced()
    func markAllPodcastsUnsyncedWhereLastSyncAtNot(_ lastSyncAt: String)
    func setPushForAllPodcasts(pushEnabled: Bool)
    func saveAutoAddToUpNextForAllPodcasts(autoAddToUpNext: Int32)
    func updateAutoAddToUpNext(to value: AutoAddToUpNextSetting, for podcasts: [Podcast])
    func setDownloadSettingForAllPodcasts(setting: AutoDownloadSetting)
    func allUnsyncedPodcasts() -> [Podcast]
    func delete(podcast: Podcast)
    @discardableResult
    func save(podcast: Podcast) -> Podcast
    func savePushSetting(podcast: Podcast, pushEnabled: Bool)
    func savePushSetting(podcastUuid: String, pushEnabled: Bool)
    func saveAutoAddToUpNext(podcastUuid: String, autoAddToUpNext: Int32)
    func savePodcastDownloadSetting(_ setting: AutoDownloadSetting, podcastUuid: String)
    func saveAutoArchiveLimit(podcast: Podcast, limit: Int32)
    func saveSortOrders(podcasts: [Podcast])
    func markAllUnarchivedForPodcast(id: Int64)
    func updateAllPodcastGrouping(to grouping: PodcastGrouping)
    func updateAllShowArchived(to showArchived: Bool)
    func setPodcastImageVersion(podcastUuid: String, version: Int)
    func setAllPodcastImageVersions(to version: Int)
    func bulkSetFolderUuid(folderUuid: String, podcastUuids: [String])
    func updatePodcastFolder(podcastUuid: String, to folderUuid: String?, sortOrder: Int32)
    func setPushDefaultForNewPodcast(_ podcast: Podcast)
    func pushEnabledPodcastsCount() -> Int

    // MARK: Async variants

    // The returned models are `Sendable` value types, so they are safe to hand
    // across the awaiting task boundary. The default implementations run the
    // synchronous requirement on a background queue; conformers can override
    // with natively async reads.
    func findPodcastAsync(uuid: String, includeUnsubscribed: Bool) async -> Podcast?

    // Completes only after the write has landed and returns the saved value
    // (with its assigned row id), so callers can use the result directly. The
    // default implementation runs the synchronous requirement on a background
    // queue; conformers can override with natively async writes.
    @discardableResult
    func saveAsync(podcast: Podcast) async -> Podcast
}

public extension PodcastRepository {
    // Conveniences mirroring DataManager's default arguments, which protocol
    // requirements cannot express.
    func allPodcasts(includeUnsubscribed: Bool) -> [Podcast] {
        allPodcasts(includeUnsubscribed: includeUnsubscribed, reloadFromDatabase: false)
    }

    func allPodcastsOrderedByTitle() -> [Podcast] {
        allPodcastsOrderedByTitle(reloadFromDatabase: false)
    }

    func allPodcastsOrderedByNewestEpisodes() -> [Podcast] {
        allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: false)
    }

    func allPodcastsOrderedByLastPlayedEpisodes() -> [Podcast] {
        allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: false)
    }

    func allPodcastsOrderedByAddedDate() -> [Podcast] {
        allPodcastsOrderedByAddedDate(reloadFromDatabase: false)
    }

    func findPodcast(uuid: String) -> Podcast? {
        findPodcast(uuid: uuid, includeUnsubscribed: false)
    }

    func findPodcastAsync(uuid: String, includeUnsubscribed: Bool) async -> Podcast? {
        await runOffMainThread { self.findPodcast(uuid: uuid, includeUnsubscribed: includeUnsubscribed) }
    }

    func findPodcastAsync(uuid: String) async -> Podcast? {
        await findPodcastAsync(uuid: uuid, includeUnsubscribed: false)
    }

    @discardableResult
    func saveAsync(podcast: Podcast) async -> Podcast {
        await runOffMainThread { self.save(podcast: podcast) }
    }
}

extension DataManager: PodcastRepository {}
