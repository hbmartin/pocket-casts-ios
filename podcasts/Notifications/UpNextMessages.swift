import Foundation
import PocketCastsUtils

/// Typed messages for the Up Next domain (migration Phase 5.3; one struct per
/// legacy `Constants.Notifications` name, past tense, no suffix). The bridged
/// raw names are effectively ABI — never change them.
///
/// The no-payload messages implement `makeMessage`/`makeNotification` explicitly
/// (rather than relying on SDK defaults) so string-based posts from unconverted
/// files — e.g. `PlaybackManager` — keep reaching typed observers, and typed
/// posts keep reaching string-based observers, throughout the migration.

/// The Up Next queue changed wholesale (reorder, clear, bulk add/delete, sync
/// replace). No payload; listeners re-query the queue.
nonisolated struct UpNextQueueChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.upNextQueueChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A single episode was added to Up Next. `uuid` is the episode uuid (nil when
/// a string-based post carried none); `addedToTop` is `true` for a "Play Next"
/// (top of queue) add, `false` for "Play Last". The bridged representation is
/// frozen during the migration: uuid rides in `object` and `addedToTop` in
/// `userInfo` under `Constants.Notifications.upNextEpisodeAddedToTopKey`.
nonisolated struct UpNextEpisodeAdded: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.upNextEpisodeAdded }

    let uuid: String?
    let addedToTop: Bool

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(
            uuid: notification.object as? String,
            addedToTop: notification.userInfo?[Constants.Notifications.upNextEpisodeAddedToTopKey] as? Bool ?? false
        )
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(
            name: Self.name,
            object: message.uuid,
            userInfo: [Constants.Notifications.upNextEpisodeAddedToTopKey: message.addedToTop]
        )
    }
}

/// A single episode was removed from Up Next. `uuid` is the episode uuid; nil
/// when a string-based post carried none.
nonisolated struct UpNextEpisodeRemoved: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.upNextEpisodeRemoved }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// Up Next shuffle was toggled; the new value lives in
/// `Settings.upNextShuffleEnabled()`. No payload.
nonisolated struct UpNextShuffleToggled: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.upNextShuffleToggle }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}
