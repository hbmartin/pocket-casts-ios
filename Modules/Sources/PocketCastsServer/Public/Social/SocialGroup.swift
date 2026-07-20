import Foundation
import SwiftProtobuf

/// A Group (Slice 13, ADR-0012): one entity, two configurations. A private
/// group is an invite-only circle; a public group is a one-tap joinable hub,
/// optionally anchored (non-exclusively) to a podcast. Content is deliberate
/// posts only — membership never grants follower-level visibility.
public struct SocialGroup: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let ownerHandle: String
    public let ownerDisplayName: String
    public let title: String
    public let description: String
    public let visibility: SocialVisibility
    public let podcastUuid: String
    public let podcastTitle: String
    public let memberCount: Int
    public let yourRole: GroupRole
    public let notifyPosts: Bool
    public let createdAt: Date?

    public init(id: Int64, ownerHandle: String = "", ownerDisplayName: String = "", title: String,
                description: String = "", visibility: SocialVisibility = .private, podcastUuid: String = "",
                podcastTitle: String = "", memberCount: Int = 0, yourRole: GroupRole = .none,
                notifyPosts: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.ownerHandle = ownerHandle
        self.ownerDisplayName = ownerDisplayName
        self.title = title
        self.description = description
        self.visibility = visibility
        self.podcastUuid = podcastUuid
        self.podcastTitle = podcastTitle
        self.memberCount = memberCount
        self.yourRole = yourRole
        self.notifyPosts = notifyPosts
        self.createdAt = createdAt
    }
}

public enum GroupRole: Int, Sendable {
    case none = 0
    case member = 1
    case owner = 2
    case invited = 3
    case banned = 4
}

/// A deliberate share into a Group: an episode, a shared list, or plain text,
/// with threaded replies carrying the comment-tree semantics.
public struct GroupPost: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let groupId: Int64
    public let parentId: Int64 // 0 = top-level
    public let userId: String
    public let handle: String
    public let displayName: String
    public let text: String
    public let episodeUuid: String
    public let podcastUuid: String
    public let episodeTitle: String
    public let podcastTitle: String
    public let listId: Int64
    public let listTitle: String
    public let createdAt: Date?
    public let edited: Bool
    public let removed: Bool
    public let replyCount: Int

    public init(id: Int64, groupId: Int64 = 0, parentId: Int64 = 0, userId: String = "",
                handle: String = "", displayName: String = "", text: String = "",
                episodeUuid: String = "", podcastUuid: String = "", episodeTitle: String = "",
                podcastTitle: String = "", listId: Int64 = 0, listTitle: String = "",
                createdAt: Date? = nil, edited: Bool = false, removed: Bool = false, replyCount: Int = 0) {
        self.id = id
        self.groupId = groupId
        self.parentId = parentId
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.text = text
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.listId = listId
        self.listTitle = listTitle
        self.createdAt = createdAt
        self.edited = edited
        self.removed = removed
        self.replyCount = replyCount
    }
}

/// The caller's groups plus pending invites (Inbox-surfaced).
public struct SocialGroupsOverview: Equatable, Sendable {
    public let groups: [SocialGroup]
    public let invites: [SocialGroup]

    public init(groups: [SocialGroup], invites: [SocialGroup]) {
        self.groups = groups
        self.invites = invites
    }
}

/// A page of group posts; the group detail rides along on top-level pages.
public struct GroupPostsPage: Equatable, Sendable {
    public let posts: [GroupPost]
    public let total: Int
    public let group: SocialGroup?

    public init(posts: [GroupPost], total: Int, group: SocialGroup? = nil) {
        self.posts = posts
        self.total = total
        self.group = group
    }
}

public struct GroupMemberInfo: Equatable, Sendable, Identifiable {
    public let handle: String
    public let displayName: String
    public let role: GroupRole
    public let joinedAt: Date?

    public var id: String { handle }

    public init(handle: String, displayName: String, role: GroupRole, joinedAt: Date? = nil) {
        self.handle = handle
        self.displayName = displayName
        self.role = role
        self.joinedAt = joinedAt
    }
}

// MARK: - Wire mapping (internal)

extension SocialGroup {
    init(_ api: Api_SocialGroup) {
        self.init(id: api.id,
                  ownerHandle: api.ownerHandle,
                  ownerDisplayName: api.ownerDisplayName,
                  title: api.title,
                  description: api.description_p,
                  visibility: SocialVisibility(rawValue: api.visibility.rawValue) ?? .private,
                  podcastUuid: api.podcastUuid,
                  podcastTitle: api.podcastTitle,
                  memberCount: Int(api.memberCount),
                  yourRole: GroupRole(rawValue: api.yourRole.rawValue) ?? .none,
                  notifyPosts: api.notifyPosts,
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil)
    }
}

extension GroupPost {
    init(_ api: Api_GroupPost) {
        self.init(id: api.id,
                  groupId: api.groupID,
                  parentId: api.parentID,
                  userId: api.userID,
                  handle: api.handle,
                  displayName: api.displayName,
                  text: api.text,
                  episodeUuid: api.episodeUuid,
                  podcastUuid: api.podcastUuid,
                  episodeTitle: api.episodeTitle,
                  podcastTitle: api.podcastTitle,
                  listId: api.listID,
                  listTitle: api.listTitle,
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  edited: api.edited,
                  removed: api.removed,
                  replyCount: Int(api.replyCount))
    }
}
