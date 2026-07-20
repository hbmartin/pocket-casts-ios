import Foundation
import SwiftProtobuf

/// One node of an episode's comment tree (Slice 6, ADR-0010). A timestamped
/// top-level comment is a "Moment" — the player renders it as a scrubber pin;
/// the episode page renders the same node in the thread. Tombstones
/// (`removed`) keep their place so replies stay anchored, with text and
/// author already wiped server-side.
public struct SocialComment: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let parentId: Int64 // 0 = top-level
    public let userId: String  // empty on tombstones
    public let handle: String
    public let displayName: String
    public let text: String
    public let timestampSeconds: Int? // nil = plain thread comment

    // Slice 12: transcript anchor. The quote is self-contained rendering
    // truth; source/segment are an advisory ref into the transcript that
    // generated it (transcripts regenerate, so never a hard dependency).
    public let quote: String
    public let quoteSource: Int
    public let quoteSegment: Int

    public let createdAt: Date?
    public let edited: Bool
    public let removed: Bool
    public let replyCount: Int

    // Populated on Inbox reply rows only.
    public let episodeUuid: String
    public let podcastUuid: String
    public let episodeTitle: String
    public let podcastTitle: String

    public init(id: Int64, parentId: Int64 = 0, userId: String = "", handle: String = "",
                displayName: String = "", text: String = "", timestampSeconds: Int? = nil,
                quote: String = "", quoteSource: Int = 0, quoteSegment: Int = 0,
                createdAt: Date? = nil, edited: Bool = false, removed: Bool = false,
                replyCount: Int = 0, episodeUuid: String = "", podcastUuid: String = "",
                episodeTitle: String = "", podcastTitle: String = "") {
        self.id = id
        self.parentId = parentId
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.text = text
        self.timestampSeconds = timestampSeconds
        self.quote = quote
        self.quoteSource = quoteSource
        self.quoteSegment = quoteSegment
        self.createdAt = createdAt
        self.edited = edited
        self.removed = removed
        self.replyCount = replyCount
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
    }
}

/// A page of comments plus the unfiltered total.
public struct SocialCommentPage: Equatable, Sendable {
    public let comments: [SocialComment]
    public let total: Int

    public init(comments: [SocialComment], total: Int) {
        self.comments = comments
        self.total = total
    }
}

/// The Inbox "Replies" page: direct replies to the caller's comments with the
/// watermark-based unread count.
public struct SocialInboxReplies: Equatable, Sendable {
    public let replies: [SocialComment]
    public let total: Int
    public let unread: Int

    public init(replies: [SocialComment], total: Int, unread: Int) {
        self.replies = replies
        self.total = total
        self.unread = unread
    }
}

// MARK: - Wire mapping (internal)

extension SocialComment {
    init(_ api: Api_SocialComment) {
        self.init(id: api.id,
                  parentId: api.parentID,
                  userId: api.userID,
                  handle: api.handle,
                  displayName: api.displayName,
                  text: api.text,
                  timestampSeconds: api.hasTimestampSeconds ? Int(api.timestampSeconds) : nil,
                  quote: api.quote,
                  quoteSource: Int(api.quoteSource),
                  quoteSegment: Int(api.quoteSegment),
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  edited: api.edited,
                  removed: api.removed,
                  replyCount: Int(api.replyCount),
                  episodeUuid: api.episodeUuid,
                  podcastUuid: api.podcastUuid,
                  episodeTitle: api.episodeTitle,
                  podcastTitle: api.podcastTitle)
    }
}
