import Foundation
import PocketCastsUtils

/// Typed messages for the episode domain (migration Phase 4+; one struct per
/// legacy `Constants.Notifications` name, past tense, no suffix). The bridged
/// raw names are effectively ABI — never change them.

/// An episode's played/unplayed status changed (played up to, play count, or
/// explicit mark as played/unplayed). `uuid` is the episode uuid; nil for bulk
/// changes where every listener should re-query.
nonisolated struct EpisodePlayStatusChanged: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.episodePlayStatusChanged }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// An episode was archived or unarchived. `uuid` is the episode uuid.
nonisolated struct EpisodeArchiveStatusChanged: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.episodeArchiveStatusChanged }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// An episode was starred or unstarred. `uuid` is the episode uuid.
nonisolated struct EpisodeStarredChanged: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.episodeStarredChanged }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// An episode finished downloading and its file is on disk. `uuid` is the
/// episode uuid.
nonisolated struct EpisodeDownloaded: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.episodeDownloaded }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// An episode's download status changed (queued, downloading, failed, removed,
/// etc). `uuid` is the episode uuid.
nonisolated struct EpisodeDownloadStatusChanged: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.episodeDownloadStatusChanged }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// An episode's duration was recalculated from the media file (or corrected via
/// a remote probe). `uuid` is the episode uuid.
nonisolated struct EpisodeDurationChanged: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.episodeDurationChanged }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A user (uploaded-files) episode's metadata changed (title, image, colors,
/// etc). `uuid` is the user episode uuid.
nonisolated struct UserEpisodeUpdated: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.userEpisodeUpdated }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// An in-flight download made progress (fires frequently while anything is
/// downloading). `uuid` is the episode uuid; listeners read the actual
/// progress from `DownloadManager.shared.progressManager`.
nonisolated struct DownloadProgressChanged: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.downloadProgress }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// A bulk episode change (mark all played, archive all, auto download pass,
/// restore cleanup, etc). Carries no payload — listeners should re-query.
nonisolated struct ManyEpisodesChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject

    static var name: Notification.Name { Constants.Notifications.manyEpisodesChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The listening history was modified (an episode was removed from it, or it
/// was cleared). Carries no payload — listeners should re-query.
nonisolated struct ListeningHistoryChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject

    static var name: Notification.Name { Constants.Notifications.listeningHistoryChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}
