import Foundation
import PocketCastsUtils

/// Progress for an in-flight transcription job, throttled by the queue manager
/// to ~1/sec. `stage` carries the job state's rawValue; `progress` is 0…1 within
/// that stage.
nonisolated struct TranscriptionProgress: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("PCTranscriptionProgress") }

    static let stageUserInfoKey = "stage"
    static let progressUserInfoKey = "progress"

    let episodeUuid: String?
    let stage: String
    let progress: Double

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(
            episodeUuid: notification.object as? String,
            stage: notification.userInfo?[stageUserInfoKey] as? String ?? "",
            progress: notification.userInfo?[progressUserInfoKey] as? Double ?? 0
        )
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(
            name: Self.name,
            object: message.episodeUuid,
            userInfo: [
                stageUserInfoKey: message.stage,
                progressUserInfoKey: message.progress,
            ]
        )
    }
}

/// A transcription job reached a terminal state. `succeeded` distinguishes
/// completed from failed/cancelled; observers re-query the record for detail.
nonisolated struct EpisodeTranscriptionCompleted: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("PCEpisodeTranscriptionCompleted") }

    static let succeededUserInfoKey = "succeeded"

    let episodeUuid: String?
    let succeeded: Bool

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(
            episodeUuid: notification.object as? String,
            succeeded: notification.userInfo?[succeededUserInfoKey] as? Bool ?? false
        )
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(
            name: Self.name,
            object: message.episodeUuid,
            userInfo: [succeededUserInfoKey: message.succeeded]
        )
    }
}
