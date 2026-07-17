import Foundation

/// Async entry points for send-to-friend + the shared-item inbox (Slice 4;
/// docs/Social.md). Ships behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Sends an episode to a joined @handle with an optional note + timestamp.
    /// False covers not-joined sender (403), unknown/blocked recipient (404),
    /// and rejected notes.
    func sendSharedItem(recipientHandle: String, episodeUuid: String, podcastUuid: String,
                        episodeTitle: String, podcastTitle: String,
                        note: String, timestampSeconds: Int) async -> Bool {
        var request = Api_SharedItemSendRequest()
        request.recipientHandle = recipientHandle
        request.episodeUuid = episodeUuid
        request.podcastUuid = podcastUuid
        request.episodeTitle = episodeTitle
        request.podcastTitle = podcastTitle
        request.note = note
        request.timestampSeconds = Int32(timestampSeconds)
        return await withCheckedContinuation { continuation in
            let operation = SharedItemSendTask(request: request)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// The caller's inbox page (requires a joined account server-side).
    func fetchInbox(limit: Int = 50, offset: Int = 0) async -> SocialInboxPage? {
        await withCheckedContinuation { continuation in
            let operation = SocialInboxListTask(limit: Int32(limit), offset: Int32(offset))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Marks the given received items read.
    func markInboxRead(ids: [Int64]) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SocialInboxReadTask(ids: ids)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Deletes one received item. Idempotent.
    func deleteInboxItem(id: Int64) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SocialInboxDeleteTask(id: id)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
