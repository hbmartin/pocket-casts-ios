import Foundation
import SwiftProtobuf

/// Follow graph + activity feed models (Slice 5, docs/Social.md, ADR-0009).

public enum FollowState: Int, Sendable {
    case none = 0
    case pending = 1
    case active = 2
}

/// One row of a followers/following/requests list.
public struct FollowEntry: Equatable, Sendable, Identifiable {
    public let handle: String
    public let displayName: String
    public let userId: String
    public let state: FollowState

    public var id: String { handle }

    public init(handle: String, displayName: String, userId: String, state: FollowState) {
        self.handle = handle
        self.displayName = displayName
        self.userId = userId
        self.state = state
    }
}

public struct FollowList: Equatable, Sendable {
    public let entries: [FollowEntry]
    public let total: Int

    public init(entries: [FollowEntry], total: Int) {
        self.entries = entries
        self.total = total
    }
}

public enum FeedItemKind: Int, Sendable {
    case joined = 1
    case followedPerson = 2
    case followedShow = 3
    case finishedEpisode = 4
    case reviewed = 5
    case reacted = 6
    case commented = 7
    case publishedList = 8
    case joinedGroup = 9
    case milestone = 10
}

/// One derived activity-feed item (read-time derivation; ADR-0009).
public struct FeedItem: Equatable, Sendable, Identifiable {
    public let kind: FeedItemKind
    public let actorHandle: String
    public let actorDisplayName: String
    public let actorUserId: String
    public let podcastUuid: String
    public let podcastTitle: String
    public let episodeUuid: String
    public let episodeTitle: String
    public let targetHandle: String
    public let reactionKind: ReactionKind?
    public let reviewExcerpt: String
    public let eventAt: Date?
    public let listTitle: String
    public let listId: Int64
    public let groupTitle: String
    public let groupId: Int64
    public let milestoneKind: Int
    public let milestoneTier: Int

    public var id: String { "\(kind.rawValue)-\(actorHandle)-\(episodeUuid)-\(podcastUuid)-\(targetHandle)-\(listId)-\(groupId)-\(milestoneKind)-\(milestoneTier)-\(eventAt?.timeIntervalSince1970 ?? 0)" }

    public init(kind: FeedItemKind, actorHandle: String, actorDisplayName: String, actorUserId: String,
                podcastUuid: String, podcastTitle: String, episodeUuid: String, episodeTitle: String,
                targetHandle: String, reactionKind: ReactionKind?, reviewExcerpt: String, eventAt: Date?,
                listTitle: String = "", listId: Int64 = 0,
                groupTitle: String = "", groupId: Int64 = 0,
                milestoneKind: Int = 0, milestoneTier: Int = 0) {
        self.kind = kind
        self.actorHandle = actorHandle
        self.actorDisplayName = actorDisplayName
        self.actorUserId = actorUserId
        self.podcastUuid = podcastUuid
        self.podcastTitle = podcastTitle
        self.episodeUuid = episodeUuid
        self.episodeTitle = episodeTitle
        self.targetHandle = targetHandle
        self.reactionKind = reactionKind
        self.reviewExcerpt = reviewExcerpt
        self.eventAt = eventAt
        self.listTitle = listTitle
        self.listId = listId
        self.groupTitle = groupTitle
        self.groupId = groupId
        self.milestoneKind = milestoneKind
        self.milestoneTier = milestoneTier
    }
}

// MARK: - Wire mapping (internal)

extension FollowState {
    init(_ api: Api_FollowState) {
        self = FollowState(rawValue: api.rawValue) ?? .none
    }
}

extension FollowEntry {
    init(_ api: Api_FollowEntry) {
        self.init(handle: api.handle, displayName: api.displayName, userId: api.userID, state: FollowState(api.state))
    }
}

extension FeedItem {
    init?(_ api: Api_FeedItem) {
        guard let kind = FeedItemKind(rawValue: api.kind.rawValue) else { return nil }
        self.init(kind: kind,
                  actorHandle: api.actorHandle,
                  actorDisplayName: api.actorDisplayName,
                  actorUserId: api.actorUserID,
                  podcastUuid: api.podcastUuid,
                  podcastTitle: api.podcastTitle,
                  episodeUuid: api.episodeUuid,
                  episodeTitle: api.episodeTitle,
                  targetHandle: api.targetHandle,
                  reactionKind: ReactionKind(rawValue: api.reactionKind.rawValue),
                  reviewExcerpt: api.reviewExcerpt,
                  eventAt: api.hasEventAt ? api.eventAt.date : nil,
                  listTitle: api.listTitle,
                  listId: api.listID,
                  groupTitle: api.groupTitle,
                  groupId: api.groupID,
                  milestoneKind: Int(api.milestoneKind),
                  milestoneTier: Int(api.milestoneTier))
    }
}
