import Foundation
import PocketCastsUtils

/// An inbound quote share link (`?t=...&q=...`) was opened for `episodeUuid`:
/// after the seek, the transcript view (if showing that episode) scrolls to and
/// briefly highlights the quoted line. Best-effort — no observer, no effect.
nonisolated struct TranscriptQuoteHighlightRequested: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJTranscriptQuoteHighlightRequested") }

    let episodeUuid: String
    let quote: String

    static func makeMessage(_ notification: Notification) -> Self? {
        guard let userInfo = notification.userInfo,
              let episodeUuid = userInfo["episodeUuid"] as? String,
              let quote = userInfo["quote"] as? String else {
            return nil
        }
        return Self(episodeUuid: episodeUuid, quote: quote)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: nil, userInfo: [
            "episodeUuid": message.episodeUuid,
            "quote": message.quote
        ])
    }
}
