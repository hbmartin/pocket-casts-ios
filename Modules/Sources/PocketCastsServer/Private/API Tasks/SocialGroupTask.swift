import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Group tasks (Slice 13; docs/Social.md, ADR-0012).

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class GroupCreateTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialGroup?) -> Void)?

    private let title: String
    private let groupDescription: String
    private let visibility: SocialVisibility
    private let podcastUuid: String
    private let podcastTitle: String

    init(title: String, description: String, visibility: SocialVisibility, podcastUuid: String, podcastTitle: String) {
        self.title = title
        groupDescription = description
        self.visibility = visibility
        self.podcastUuid = podcastUuid
        self.podcastTitle = podcastTitle
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_GroupCreateRequest()
            request.title = title
            request.description_p = groupDescription
            request.visibility = visibility.apiValue
            request.podcastUuid = podcastUuid
            request.podcastTitle = podcastTitle
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/group/create", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("GroupCreateTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            completion?(SocialGroup(try Api_SocialGroup(serializedBytes: responseData)))
        } catch {
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class GroupAckTask: ApiBaseTask, @unchecked Sendable {
    enum Kind {
        case update(groupId: Int64, title: String, description: String, visibility: SocialVisibility)
        case delete(groupId: Int64)
        case join(groupId: Int64)
        case leave(groupId: Int64)
        case invite(groupId: Int64, handle: String)
        case inviteRespond(groupId: Int64, accept: Bool)
        case kick(groupId: Int64, handle: String, ban: Bool)
        case alert(groupId: Int64, enabled: Bool)
        case postEdit(postId: Int64, text: String)
        case postDelete(postId: Int64)
    }

    var completion: ((Bool) -> Void)?

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            switch kind {
            case .update(let groupId, let title, let description, let visibility):
                var request = Api_GroupUpdateRequest()
                request.id = groupId
                request.title = title
                request.description_p = description
                request.visibility = visibility.apiValue
                data = try request.serializedData()
                path = "social/group/update"
            case .delete(let groupId):
                var request = Api_GroupDeleteRequest()
                request.id = groupId
                data = try request.serializedData()
                path = "social/group/delete"
            case .join(let groupId):
                var request = Api_GroupJoinRequest()
                request.id = groupId
                data = try request.serializedData()
                path = "social/group/join"
            case .leave(let groupId):
                var request = Api_GroupLeaveRequest()
                request.id = groupId
                data = try request.serializedData()
                path = "social/group/leave"
            case .invite(let groupId, let handle):
                var request = Api_GroupInviteRequest()
                request.groupID = groupId
                request.handle = handle
                data = try request.serializedData()
                path = "social/group/invite"
            case .inviteRespond(let groupId, let accept):
                var request = Api_GroupInviteRespondRequest()
                request.groupID = groupId
                request.accept = accept
                data = try request.serializedData()
                path = "social/group/invite/respond"
            case .kick(let groupId, let handle, let ban):
                var request = Api_GroupKickRequest()
                request.groupID = groupId
                request.handle = handle
                request.ban = ban
                data = try request.serializedData()
                path = "social/group/kick"
            case .alert(let groupId, let enabled):
                var request = Api_GroupAlertRequest()
                request.groupID = groupId
                request.enabled = enabled
                data = try request.serializedData()
                path = "social/group/alert"
            case .postEdit(let postId, let text):
                var request = Api_GroupPostEditRequest()
                request.id = postId
                request.text = text
                data = try request.serializedData()
                path = "social/group/post/edit"
            case .postDelete(let postId):
                var request = Api_GroupPostDeleteRequest()
                request.id = postId
                data = try request.serializedData()
                path = "social/group/post/delete"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("GroupAckTask \(path) failed, http status \(httpStatus)")
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
class GroupsFetchTask: ApiBaseTask, @unchecked Sendable {
    enum Kind {
        case mine
        case discover(limit: Int)
        case forPodcast(uuid: String)
    }

    var completion: ((SocialGroupsOverview?) -> Void)?

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            switch kind {
            case .mine:
                data = try Api_GroupsRequest().serializedData()
                path = "social/groups"
            case .discover(let limit):
                var request = Api_GroupDiscoverRequest()
                request.limit = Int32(limit)
                data = try request.serializedData()
                path = "social/group/discover"
            case .forPodcast(let uuid):
                var request = Api_GroupsForPodcastRequest()
                request.podcastUuid = uuid
                data = try request.serializedData()
                path = "social/group/for-podcast"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("GroupsFetchTask \(path) failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            if case .mine = kind {
                let parsed = try Api_GroupsResponse(serializedBytes: responseData)
                completion?(SocialGroupsOverview(groups: parsed.groups.map(SocialGroup.init),
                                                 invites: parsed.invites.map(SocialGroup.init)))
            } else {
                let parsed = try Api_GroupDiscoverResponse(serializedBytes: responseData)
                completion?(SocialGroupsOverview(groups: parsed.groups.map(SocialGroup.init), invites: []))
            }
        } catch {
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class GroupPostSubmitTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((GroupPost?) -> Void)?

    private let groupId: Int64
    private let parentId: Int64
    private let text: String
    private let episodeUuid: String
    private let podcastUuid: String
    private let episodeTitle: String
    private let podcastTitle: String
    private let listId: Int64
    private let listTitle: String

    init(groupId: Int64, parentId: Int64, text: String, episodeUuid: String, podcastUuid: String,
         episodeTitle: String, podcastTitle: String, listId: Int64, listTitle: String) {
        self.groupId = groupId
        self.parentId = parentId
        self.text = text
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.listId = listId
        self.listTitle = listTitle
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_GroupPostRequest()
            request.groupID = groupId
            request.parentID = parentId
            request.text = text
            request.episodeUuid = episodeUuid
            request.podcastUuid = podcastUuid
            request.episodeTitle = episodeTitle
            request.podcastTitle = podcastTitle
            request.listID = listId
            request.listTitle = listTitle
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/group/post/submit", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("GroupPostSubmitTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            completion?(GroupPost(try Api_GroupPost(serializedBytes: responseData)))
        } catch {
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class GroupPostsTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((GroupPostsPage?) -> Void)?

    private let groupId: Int64
    private let parentId: Int64
    private let limit: Int32
    private let offset: Int32

    init(groupId: Int64, parentId: Int64, limit: Int32, offset: Int32) {
        self.groupId = groupId
        self.parentId = parentId
        self.limit = limit
        self.offset = offset
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_GroupPostsRequest()
            request.groupID = groupId
            request.parentID = parentId
            request.limit = limit
            request.offset = offset
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/group/posts", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("GroupPostsTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            let parsed = try Api_GroupPostsResponse(serializedBytes: responseData)
            completion?(GroupPostsPage(posts: parsed.posts.map(GroupPost.init),
                                       total: Int(parsed.total),
                                       group: parsed.hasGroup ? SocialGroup(parsed.group) : nil))
        } catch {
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class GroupMembersTask: ApiBaseTask, @unchecked Sendable {
    var completion: (([GroupMemberInfo]?) -> Void)?

    private let groupId: Int64

    init(groupId: Int64) {
        self.groupId = groupId
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_GroupMembersRequest()
            request.groupID = groupId
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/group/members", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("GroupMembersTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            let parsed = try Api_GroupMembersResponse(serializedBytes: responseData)
            completion?(parsed.members.map {
                GroupMemberInfo(handle: $0.handle, displayName: $0.displayName,
                                role: GroupRole(rawValue: $0.role.rawValue) ?? .member,
                                joinedAt: $0.hasJoinedAt ? $0.joinedAt.date : nil)
            })
        } catch {
            completion?(nil)
        }
    }
}
