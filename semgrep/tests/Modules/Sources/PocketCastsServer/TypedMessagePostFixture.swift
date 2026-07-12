import Foundation

/// Fixture for pocketcasts.no-direct-typed-notification-post: typed messages must be
/// posted through NotificationCenter.postOnMainThread(_:), never the SDK's typed
/// post(_:), which drops the bridged object/userInfo for string-based observers.
/// Lives under the Server-module test path so the co-firing
/// pocketcasts.server-module-post-on-main-thread expectations are also real.
class TypedMessagePostFixture {
    func postsTypedMessageDirectly() {
        // ruleid: pocketcasts.no-direct-typed-notification-post, pocketcasts.server-module-post-on-main-thread
        NotificationCenter.default.post(SubscriptionStatusChanged())
    }

    func postsTypedMessageWithPayloadDirectly() {
        // ruleid: pocketcasts.no-direct-typed-notification-post, pocketcasts.server-module-post-on-main-thread
        NotificationCenter.default.post(UserWillBeSignedOut(userInitiated: false))
    }

    func postsViaMainThreadHelper() {
        // ok: pocketcasts.no-direct-typed-notification-post
        NotificationCenter.postOnMainThread(SubscriptionStatusChanged())
    }

    func postsLegacyNotificationValue() {
        // ok: pocketcasts.no-direct-typed-notification-post
        // ruleid: pocketcasts.server-module-post-on-main-thread
        NotificationCenter.default.post(Notification(name: ServerNotifications.subscriptionStatusChanged))
    }

    func postsLegacyStringName() {
        // ok: pocketcasts.no-direct-typed-notification-post
        // ruleid: pocketcasts.server-module-post-on-main-thread
        NotificationCenter.default.post(name: ServerNotifications.subscriptionStatusChanged, object: nil)
    }
}
