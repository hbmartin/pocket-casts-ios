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
