import Foundation

/// Async entry points for the episode comment tree (Slice 6; docs/Social.md,
/// ADR-0010). Ships behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Posts a top-level comment (timestamped = a Moment) or, with parentId,
    /// a reply. The server enforces the joined requirement and the seed-only
    /// listen-gate; nil covers rejection and failure alike.
    func submitComment(episodeUuid: String, podcastUuid: String, episodeTitle: String = "",
                       podcastTitle: String = "", text: String, parentId: Int64 = 0,
                       timestampSeconds: Int? = nil, quote: String = "",
                       quoteSource: Int = 0, quoteSegment: Int = 0) async -> SocialComment? {
        await withCheckedContinuation { continuation in
            let operation = CommentSubmitTask(episodeUuid: episodeUuid, podcastUuid: podcastUuid,
                                              episodeTitle: episodeTitle, podcastTitle: podcastTitle,
                                              text: text, parentId: parentId, timestampSeconds: timestampSeconds,
                                              quote: quote, quoteSource: quoteSource, quoteSegment: quoteSegment)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Grace-window edit: the server rejects once replied-to or expired.
    func editComment(id: Int64, text: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = CommentEditTask(commentId: id, text: text, delete: false)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Tombstones the caller's comment (ADR-0010): replies survive.
    func deleteComment(id: Int64) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = CommentEditTask(commentId: id, text: "", delete: true)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// The episode's top-level page, newest first (tombstones included).
    func fetchEpisodeComments(episodeUuid: String, limit: Int = 50, offset: Int = 0) async -> SocialCommentPage? {
        await withCheckedContinuation { continuation in
            let operation = CommentListTask(episodeUuid: episodeUuid, parentId: 0,
                                            limit: Int32(limit), offset: Int32(offset))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// One node's direct children, oldest first — branches expand on demand.
    func fetchCommentReplies(parentId: Int64, limit: Int = 50, offset: Int = 0) async -> SocialCommentPage? {
        await withCheckedContinuation { continuation in
            let operation = CommentListTask(episodeUuid: "", parentId: parentId,
                                            limit: Int32(limit), offset: Int32(offset))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Direct replies to the caller's comments, with the watermark unread.
    func fetchInboxReplies(limit: Int = 50, offset: Int = 0) async -> SocialInboxReplies? {
        await withCheckedContinuation { continuation in
            let operation = InboxRepliesTask(limit: Int32(limit), offset: Int32(offset), markSeen: false)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Advances the replies seen-watermark (everything listed counts as read).
    @discardableResult
    func markInboxRepliesSeen() async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = InboxRepliesTask(limit: 0, offset: 0, markSeen: true)
            operation.completion = { continuation.resume(returning: $0 != nil) }
            apiQueue.addOperation(operation)
        }
    }
}
