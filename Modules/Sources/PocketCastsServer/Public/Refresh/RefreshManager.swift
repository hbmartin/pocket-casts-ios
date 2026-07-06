import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

// @unchecked Sendable: the only stored property is an OperationQueue (thread-safe).
public final class RefreshManager: @unchecked Sendable {
    public static let shared = RefreshManager()

    let refreshQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private static let minTimeBetweenRefreshes = 15.seconds

    public func syncUpNext() {
        if !SyncManager.isUserLoggedIn() { return }

        // sync custom episodes in their Up Next
        refreshQueue.addOperation(RetrieveCustomFilesTask())
        refreshQueue.addOperation(UpNextSyncTask())
    }


    /// Updates a podcast and all the associated information.
    ///
    /// Note that this will force all the episodes to be updated.
    /// - Parameter podcast: a `Podcast` object
    public func refresh(podcast: Podcast, from episodeUuid: String) {
        // Podcast is a value type: carry the transient force-refresh flag on the copy handed to the
        // refresh pipeline. (The old post-refresh `forceRefreshEpisodeFrom = nil` reset was a no-op on
        // a transient field of an instance the pipeline had already consumed, so it is dropped.)
        var podcast = podcast
        podcast.forceRefreshEpisodeFrom = episodeUuid
        let podcastToRefresh = podcast
        let podcastUuid = podcast.uuid

        refresh(podcasts: [podcastToRefresh]) {
            if SyncManager.isUserLoggedIn() {
                guard let episodes = ApiServerHandler.shared.retrieveEpisodeTaskSynchronouusly(podcastUuid: podcastUuid) else { return }

                DataManager.sharedManager.saveBulkEpisodeSyncInfo(episodes: DataConverter.convert(syncInfoEpisodes: episodes))
            }
        }
    }

    public func refresh(podcast: Podcast, from episodeUuid: String) async {
        var podcast = podcast
        podcast.forceRefreshEpisodeFrom = episodeUuid
        let podcastToRefresh = podcast
        let podcastUuid = podcast.uuid

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refresh(podcasts: [podcastToRefresh]) {
                defer { continuation.resume() }
                if SyncManager.isUserLoggedIn() {
                    guard let episodes = ApiServerHandler.shared.retrieveEpisodeTaskSynchronouusly(podcastUuid: podcastUuid) else { return }

                    DataManager.sharedManager.saveBulkEpisodeSyncInfo(episodes: DataConverter.convert(syncInfoEpisodes: episodes))
                }
            }
        }
    }

    public func refreshPodcasts(forceEvenIfRefreshedRecently: Bool = false) {
        if !forceEvenIfRefreshedRecently {
            if let lastRefreshStartTime = ServerSettings.lastRefreshStartTime(), fabs(lastRefreshStartTime.timeIntervalSinceNow) < RefreshManager.minTimeBetweenRefreshes {
                // if it's been less than minTimeBetweenRefreshes since our last refresh, don't do another one. Effectively throttling user refreshes a little bit
                FileLog.shared.addMessage("Refresh - Throttled")
                DispatchQueue.global().async {
                    Thread.sleep(forTimeInterval: 1.second)
                    ServerNotificationsHelper.shared.firePodcastsUpdated()
                    NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastRefreshThrottled, object: nil)
                }

                return
            }
        }

        refresh(podcasts: DataManager.sharedManager.allPodcasts(includeUnsubscribed: false))
    }

    private func refresh(podcasts: [Podcast], completion: (@Sendable () -> Void)? = nil) {
        UserDefaults.standard.set(Date(), forKey: ServerConstants.UserDefaults.lastRefreshStartTime)

        DispatchQueue.global().async {
            MainServerHandler.shared.refresh(podcasts: podcasts) { [weak self] refreshResponse in
                guard let self else { return }

                self.processPodcastRefreshResponse(refreshResponse) { _ in
                    completion?()
                }
            }
        }
    }


    public func refreshPodcasts(completion: @escaping @Sendable (RefreshFetchResult) -> Void) {
        DispatchQueue.global().async {
            let podcasts = DataManager.sharedManager.allPodcasts(includeUnsubscribed: false)
            MainServerHandler.shared.refresh(podcasts: podcasts) { [weak self] refreshResponse in
                guard let self else { return }

                self.processPodcastRefreshResponse(refreshResponse, completion: completion)
            }
        }
    }

    public func cancelAllRefreshes() {
        refreshQueue.cancelAllOperations()
    }

    // `internal` (not `private`) so `RefreshManagerTests` can drive the no-result branch directly.
    func processPodcastRefreshResponse(_ refreshResponse: PodcastRefreshResponse?, completion: ((RefreshFetchResult) -> Void)?) {
        guard let response = refreshResponse, response.success() else {
            FileLog.shared.addMessage("Podcast refresh failed with message: \(refreshResponse?.message ?? "none"). See previous log for more details.")
            ServerNotificationsHelper.shared.firePodcastRefreshFailed()
            completion?(.failed)

            return
        }

        if let result = response.result {
            let refreshOperation = RefreshOperation(result: result, completionHandler: completion)
            refreshQueue.addOperation(refreshOperation)
        } else {
            // Refresh succeeded but carried no result to process; report no data so the
            // completion always fires (callers may rely on it, e.g. background-fetch and
            // notification handlers that must call their own completion handler).
            ServerNotificationsHelper.shared.firePodcastRefreshSucceeded()
            completion?(.noData)
        }
    }
}
