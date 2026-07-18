import Foundation
import SwiftProtobuf

/// Shared lists (Slice 7, ADR-0011): first-class multi-writer server objects
/// that local playlists mirror. Visibility reuses the ADR-0006 tiers; the
/// list dies with its owner; entry attribution outlives nothing — erasure
/// wipes it while entries survive.

public enum SharedListRole: Int, Sendable {
    case none = 0
    case owner = 1
    case collaborator = 2
    case subscriber = 3
    case invited = 4

    public var canEdit: Bool { self == .owner || self == .collaborator }
}

public struct SharedListMember: Equatable, Sendable, Identifiable {
    public let handle: String
    public let displayName: String
    public let role: SharedListRole

    public var id: String { handle }

    public init(handle: String, displayName: String, role: SharedListRole) {
        self.handle = handle
        self.displayName = displayName
        self.role = role
    }
}

public struct SharedList: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let ownerHandle: String
    public let ownerDisplayName: String
    public let title: String
    public let description: String
    public let visibility: SocialVisibility
    public let createdAt: Date?
    public let updatedAt: Date?
    public let entryCount: Int
    public let yourRole: SharedListRole
    public let members: [SharedListMember]

    public init(id: Int64, ownerHandle: String = "", ownerDisplayName: String = "",
                title: String, description: String = "", visibility: SocialVisibility = .private,
                createdAt: Date? = nil, updatedAt: Date? = nil, entryCount: Int = 0,
                yourRole: SharedListRole = .none, members: [SharedListMember] = []) {
        self.id = id
        self.ownerHandle = ownerHandle
        self.ownerDisplayName = ownerDisplayName
        self.title = title
        self.description = description
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entryCount = entryCount
        self.yourRole = yourRole
        self.members = members
    }
}

public struct SharedListEntry: Equatable, Sendable, Identifiable {
    public let episodeUuid: String
    public let podcastUuid: String
    public let episodeTitle: String
    public let podcastTitle: String
    public let position: Int
    public let addedByHandle: String // empty when the adder was erased
    public let addedAt: Date?

    public var id: String { episodeUuid }

    public init(episodeUuid: String, podcastUuid: String = "", episodeTitle: String = "",
                podcastTitle: String = "", position: Int = 0, addedByHandle: String = "",
                addedAt: Date? = nil) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.position = position
        self.addedByHandle = addedByHandle
        self.addedAt = addedAt
    }
}

/// A shared list's header + one entries page.
public struct SharedListPage: Equatable, Sendable {
    public let list: SharedList
    public let entries: [SharedListEntry]
    public let total: Int

    public init(list: SharedList, entries: [SharedListEntry], total: Int) {
        self.list = list
        self.entries = entries
        self.total = total
    }
}

/// Everything the caller participates in, plus pending invites.
public struct SharedListsOverview: Equatable, Sendable {
    public let lists: [SharedList]
    public let invites: [SharedList]

    public init(lists: [SharedList], invites: [SharedList]) {
        self.lists = lists
        self.invites = invites
    }
}

public enum SharedListOp: Int, Sendable {
    case add = 1
    case remove = 2
    case move = 3
}

// MARK: - Wire mapping (internal)

extension SharedListRole {
    init(_ api: Api_SharedListRole) {
        self = SharedListRole(rawValue: api.rawValue) ?? .none
    }
}

extension SharedList {
    init(_ api: Api_SharedList) {
        self.init(id: api.id,
                  ownerHandle: api.ownerHandle,
                  ownerDisplayName: api.ownerDisplayName,
                  title: api.title,
                  description: api.description_p,
                  visibility: SocialVisibility(api.visibility),
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  updatedAt: api.hasUpdatedAt ? api.updatedAt.date : nil,
                  entryCount: Int(api.entryCount),
                  yourRole: SharedListRole(api.yourRole),
                  members: api.members.map {
                      SharedListMember(handle: $0.handle, displayName: $0.displayName, role: SharedListRole($0.role))
                  })
    }
}

extension SharedListEntry {
    init(_ api: Api_SharedListEntry) {
        self.init(episodeUuid: api.episodeUuid,
                  podcastUuid: api.podcastUuid,
                  episodeTitle: api.episodeTitle,
                  podcastTitle: api.podcastTitle,
                  position: Int(api.position),
                  addedByHandle: api.addedByHandle,
                  addedAt: api.hasAddedAt ? api.addedAt.date : nil)
    }
}
