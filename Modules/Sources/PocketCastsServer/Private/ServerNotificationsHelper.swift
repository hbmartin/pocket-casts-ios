import Foundation
import PocketCastsUtils

// Stateless notification poster; safe to share.
final class ServerNotificationsHelper: Sendable {
    static let shared = ServerNotificationsHelper()

    func firePodcastRefreshFailed() {
        ServerSettings.setLastRefreshSucceeded(false)

        NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastRefreshFailed, object: nil)
    }

    func firePodcastRefreshSucceeded() {
        ServerSettings.setLastRefreshSucceeded(true)

        NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastsRefreshed, object: nil)
    }

    func firePodcastsUpdated() {
        // TODO: this is the same notification as above, since it's what the app expects, but in future should we make it its own thing?
        NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastsRefreshed, object: nil)
    }

    func fireSyncCompleted() {
        ServerSettings.setLastSyncSucceeded(true)
        SyncManager.syncReason = nil

        NotificationCenter.postOnMainThread(notification: ServerNotifications.syncCompleted, object: nil)
    }

    func fireSyncFailed() {
        ServerSettings.setLastSyncSucceeded(false)
        SyncManager.syncReason = nil

        NotificationCenter.postOnMainThread(notification: ServerNotifications.syncFailed, object: nil)
    }
}
