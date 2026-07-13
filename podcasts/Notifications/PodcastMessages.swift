import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Typed messages for the podcast/folder/filter/discover domain (migration
/// Phase 5.4; one struct per legacy `Constants.Notifications` name, past
/// tense, no suffix). The bridged raw names are effectively ABI — never
/// change them.
///
/// The non-uuid messages implement `makeMessage`/`makeNotification` explicitly
/// (rather than relying on SDK defaults) so string-based posts from unconverted
/// files — e.g. `PlaybackManager`, `Settings` — keep reaching typed observers,
/// and typed posts keep reaching string-based observers, throughout the
/// migration.

/// A podcast's stored settings or metadata changed (auto-download, push,
/// auto-add-to-Up-Next, playback effects, grouping, artwork refresh, sync
/// update, etc). `uuid` is the podcast uuid.
nonisolated struct PodcastUpdated: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.podcastUpdated }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A podcast was subscribed to / added to the library. `uuid` is the podcast
/// uuid.
nonisolated struct PodcastAdded: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.podcastAdded }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A podcast was unsubscribed from / deleted from the library. `uuid` is the
/// podcast uuid.
nonisolated struct PodcastDeleted: UuidBridgedMessage {
    static var name: Notification.Name { Notification.Name("SJPodDeleted") }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A podcast's theme colors finished downloading and are cached. `uuid` is the
/// podcast uuid.
nonisolated struct PodcastColorsDownloaded: UuidBridgedMessage {
    static var name: Notification.Name { Notification.Name("SJPodcastColorsReady") }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// The podcast artwork caches were cleared (theme change or manual cache
/// clear); artwork views should re-request their images. No payload.
nonisolated struct PodcastImageReCacheRequired: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("PCPodcastImageReCacheRequired") }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A folder changed (renamed, recolored, podcasts added/removed, or a podcast
/// moved between folders). `uuid` is the folder uuid; nil when a podcast was
/// removed to the home grid and every listener should re-query.
nonisolated struct FolderChanged: UuidBridgedMessage {
    static var name: Notification.Name { Notification.Name("SJFolderChanged") }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A folder was deleted. `uuid` is the folder uuid.
nonisolated struct FolderDeleted: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.folderDeleted }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// The folder edit screen was dismissed after edits. `uuid` is the folder
/// uuid.
nonisolated struct FolderEdited: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.folderEdited }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A playlist (episode filter) was created, edited, or deleted, or the
/// playlist list changed wholesale (sync, unsubscribe cleanup). `playlist` is
/// the saved filter; nil for bulk changes where every listener should
/// re-query. The bridged representation is frozen during the migration: the
/// filter rides in `Notification.object` (raw name "FilterChanged").
nonisolated struct PlaylistChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playlistChanged }

    let playlist: EpisodeFilter?

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(playlist: notification.object as? EpisodeFilter)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.playlist)
    }
}

/// An OPML import finished and its podcasts were added. No payload.
nonisolated struct OpmlImportCompleted: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJOpmlImportCompleted") }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// An OPML import failed. No payload.
nonisolated struct OpmlImportFailed: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJOpmlImportFailed") }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A podcast search was requested from the search history or predictive list;
/// the search bar adopts `term` as its text. `term` is nil when a string-based
/// post carried none. The bridged representation is frozen during the
/// migration: the term rides in `Notification.object`.
nonisolated struct PodcastSearchRequested: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("PodcastSearchRequest") }

    let term: String?

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(term: notification.object as? String)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.term)
    }
}

/// The Discover charts region changed in settings (or the developer menu). No
/// payload.
nonisolated struct ChartRegionChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJChartRegionChanged") }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}
