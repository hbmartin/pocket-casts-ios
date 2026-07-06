import Foundation

class ServerPostOnMainFixture {
    func firesOffMain() {
        // ruleid: pocketcasts.server-module-post-on-main-thread
        NotificationCenter.default.post(name: ServerNotifications.podcastsRefreshed, object: nil)
    }

    func firesOnMain() {
        // ok: pocketcasts.server-module-post-on-main-thread
        NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastsRefreshed, object: nil)
    }

    func firesWithPayload(_ uuid: String) {
        // ruleid: pocketcasts.server-module-post-on-main-thread
        NotificationCenter.default.post(name: ServerNotifications.userEpisodeUploadStatusChanged, object: uuid)
    }
}
