import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Follow graph + activity feed tasks (Slice 5; docs/Social.md, ADR-0009).

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class FollowTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((FollowState?) -> Void)?

    private let handle: String
    private let unfollow: Bool

    init(handle: String, unfollow: Bool) {
        self.handle = handle
        self.unfollow = unfollow
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            if unfollow {
                var request = Api_UnfollowRequest()
                request.handle = handle
                data = try request.serializedData()
                path = "social/unfollow"
            } else {
                var request = Api_FollowRequest()
                request.handle = handle
                data = try request.serializedData()
                path = "social/follow"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("FollowTask \(path) failed for \(handle), http status \(httpStatus)")
                completion?(nil)
                return
            }
            if unfollow {
                let ack = try? Api_SocialAck(serializedBytes: responseData)
                completion?((ack?.success ?? false) ? FollowState.none : nil)
            } else {
                let result = try Api_FollowResponse(serializedBytes: responseData)
                completion?(FollowState(result.state))
            }
        } catch {
            FileLog.shared.addMessage("FollowTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class FollowListTask: ApiBaseTask, @unchecked Sendable {
    enum Kind { case followers, following, requests }

    var completion: ((FollowList?) -> Void)?

    private let kind: Kind
    private let limit: Int32
    private let offset: Int32

    init(kind: Kind, limit: Int32, offset: Int32) {
        self.kind = kind
        self.limit = limit
        self.offset = offset
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            if kind == .requests {
                var request = Api_FollowRequestsRequest()
                request.limit = limit
                request.offset = offset
                data = try request.serializedData()
                path = "social/follow/requests"
            } else {
                var request = Api_FollowListRequest()
                request.limit = limit
                request.offset = offset
                request.followers = kind == .followers
                data = try request.serializedData()
                path = "social/follows"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_FollowListResponse(serializedBytes: responseData)
            completion?(FollowList(entries: result.entries.map(FollowEntry.init), total: Int(result.total)))
        } catch {
            FileLog.shared.addMessage("FollowListTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class FollowApproveTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let requesterHandle: String
    private let accept: Bool

    init(requesterHandle: String, accept: Bool) {
        self.requesterHandle = requesterHandle
        self.accept = accept
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_FollowApprovalRequest()
            request.requesterHandle = requesterHandle
            request.accept = accept
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/follow/approve", token: token, data: data)
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
class SocialFeedTask: ApiBaseTask, @unchecked Sendable {
    var completion: (([FeedItem]?) -> Void)?

    private let limit: Int32
    private let beforeUnixMs: Int64

    init(limit: Int32, beforeUnixMs: Int64) {
        self.limit = limit
        self.beforeUnixMs = beforeUnixMs
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_FeedRequest()
            request.limit = limit
            request.beforeUnixMs = beforeUnixMs
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/feed", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SocialFeedTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_FeedResponse(serializedBytes: responseData)
            completion?(result.items.compactMap(FeedItem.init))
        } catch {
            FileLog.shared.addMessage("SocialFeedTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}
