import Foundation
import PocketCastsUtils

/// The unified transcript index gained (or replaced) an episode's segments —
/// either corpus source. Spotlight re-indexes the episode so its item picks up
/// the transcript text. `uuid` is the episode uuid.
nonisolated struct TranscriptIndexUpdated: UuidBridgedMessage {
    static var name: Notification.Name { Notification.Name("SJTranscriptIndexUpdated") }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}
