import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Episode comment-tree tasks (Slice 6; docs/Social.md, ADR-0010).

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class CommentSubmitTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialComment?) -> Void)?

    private let episodeUuid: String
    private let podcastUuid: String
    private let episodeTitle: String
    private let podcastTitle: String
    private let text: String
    private let parentId: Int64
    private let timestampSeconds: Int?
    private let quote: String
    private let quoteSource: Int
    private let quoteSegment: Int

    init(episodeUuid: String, podcastUuid: String, episodeTitle: String, podcastTitle: String,
         text: String, parentId: Int64, timestampSeconds: Int?,
         quote: String, quoteSource: Int, quoteSegment: Int) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.text = text
        self.parentId = parentId
        self.timestampSeconds = timestampSeconds
        self.quote = quote
        self.quoteSource = quoteSource
        self.quoteSegment = quoteSegment
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_CommentSubmitRequest()
            request.episodeUuid = episodeUuid
            request.podcastUuid = podcastUuid
            request.episodeTitle = episodeTitle
            request.podcastTitle = podcastTitle
            request.text = text
            request.parentID = parentId
            if let timestampSeconds {
                request.timestampSeconds = Int32(timestampSeconds)
            }
            request.quote = quote
            request.quoteSource = Int32(quoteSource)
            request.quoteSegment = Int32(quoteSegment)
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/comment/submit", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("CommentSubmitTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            completion?(SocialComment(try Api_SocialComment(serializedBytes: responseData)))
        } catch {
            FileLog.shared.addMessage("CommentSubmitTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class CommentEditTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let commentId: Int64
    private let text: String
    private let delete: Bool

    init(commentId: Int64, text: String, delete: Bool) {
        self.commentId = commentId
        self.text = text
        self.delete = delete
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            if delete {
                var request = Api_CommentDeleteRequest()
                request.id = commentId
                data = try request.serializedData()
                path = "social/comment/delete"
            } else {
                var request = Api_CommentEditRequest()
                request.id = commentId
                request.text = text
                data = try request.serializedData()
                path = "social/comment/edit"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(false)
                return
            }
            completion?((try? Api_SocialAck(serializedBytes: responseData))?.success ?? false)
        } catch {
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class CommentListTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialCommentPage?) -> Void)?

    private let episodeUuid: String
    private let parentId: Int64
    private let limit: Int32
    private let offset: Int32

    /// parentId 0 fetches the episode's top-level page; > 0 fetches a node's
    /// direct children (the UI expands branches on demand).
    init(episodeUuid: String, parentId: Int64, limit: Int32, offset: Int32) {
        self.episodeUuid = episodeUuid
        self.parentId = parentId
        self.limit = limit
        self.offset = offset
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            if parentId > 0 {
                var request = Api_CommentRepliesRequest()
                request.parentID = parentId
                request.limit = limit
                request.offset = offset
                data = try request.serializedData()
                path = "social/comment/replies"
            } else {
                var request = Api_EpisodeCommentsRequest()
                request.episodeUuid = episodeUuid
                request.limit = limit
                request.offset = offset
                data = try request.serializedData()
                path = "episode/comments"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_CommentsResponse(serializedBytes: responseData)
            completion?(SocialCommentPage(comments: result.comments.map(SocialComment.init), total: Int(result.total)))
        } catch {
            FileLog.shared.addMessage("CommentListTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class InboxRepliesTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialInboxReplies?) -> Void)?

    private let limit: Int32
    private let offset: Int32
    private let markSeen: Bool

    init(limit: Int32, offset: Int32, markSeen: Bool) {
        self.limit = limit
        self.offset = offset
        self.markSeen = markSeen
    }

    override func apiTokenAcquired(token: String) {
        do {
            if markSeen {
                let data = try Api_InboxRepliesRequest().serializedData()
                let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/inbox/replies/seen", token: token, data: data)
                guard response != nil, httpStatus == ServerConstants.HttpConstants.ok else {
                    completion?(nil)
                    return
                }
                completion?(SocialInboxReplies(replies: [], total: 0, unread: 0))
                return
            }

            var request = Api_InboxRepliesRequest()
            request.limit = limit
            request.offset = offset
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/inbox/replies", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_InboxRepliesResponse(serializedBytes: responseData)
            completion?(SocialInboxReplies(replies: result.replies.map(SocialComment.init),
                                           total: Int(result.total), unread: Int(result.unread)))
        } catch {
            FileLog.shared.addMessage("InboxRepliesTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}
