import Foundation
import PocketCastsUtils

// Stateless notification poster; safe to share.
final class ServerNotificationsHelper: Sendable {
    static let shared = ServerNotificationsHelper()

    func firePodcastRefreshFailed() {
        ServerSettings.setLastRefreshSucceeded(false)

        NotificationCenter.postOnMainThread(PodcastRefreshFailed())
    }

    func firePodcastRefreshSucceeded() {
        ServerSettings.setLastRefreshSucceeded(true)

        NotificationCenter.postOnMainThread(PodcastsRefreshed())
    }

    func firePodcastsUpdated() {
        // TODO: this is the same notification as above, since it's what the app expects, but in future should we make it its own thing?
        NotificationCenter.postOnMainThread(PodcastsRefreshed())
    }

    func fireSyncCompleted() {
        ServerSettings.setLastSyncSucceeded(true)
        SyncManager.syncReason = nil

        NotificationCenter.postOnMainThread(SyncCompleted())
    }

    func fireSyncFailed() {
        ServerSettings.setLastSyncSucceeded(false)
        SyncManager.syncReason = nil

        NotificationCenter.postOnMainThread(SyncFailed())
    }
}
