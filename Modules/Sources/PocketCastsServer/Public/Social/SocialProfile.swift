import Foundation
import SwiftProtobuf

/// Per-field profile visibility — the public Swift mirror of the wire
/// `Api_SocialVisibility`. Stored three-tier from day one; the Phase-1 UI only
/// writes `.private`/`.public`, and `.followersOnly` unlocks with the Phase-2
/// graph. An unknown/unspecified wire value maps to `.private` — fail safe
/// toward hidden. See ADR-0006.
public enum SocialVisibility: Int, Sendable, CaseIterable, Codable {
    case `private` = 1
    case `public` = 2
    case followersOnly = 3
}

/// A user's own social profile as seen by the app: identity keyed to the
/// immutable account uuid, an immutable handle, and per-field visibility. Value
/// type mapped from the wire `Api_SocialProfile`. See docs/Social.md and
/// ADR-0005/0006.
public struct SocialProfile: Equatable, Sendable, Codable {
    public let userId: String
    public let handle: String
    public var displayName: String
    public var bio: String
    public var avatarURL: String
    public let createdAt: Date?
    public let termsVersion: Int

    // Per-field visibility. `displayName` has no tier — it is always public once
    // joined, as the addressable identity.
    public var avatarVisibility: SocialVisibility
    public var bioVisibility: SocialVisibility
    public var followedShowsVisibility: SocialVisibility
    public var topPodcastsVisibility: SocialVisibility
    public var statsVisibility: SocialVisibility
    public var historyVisibility: SocialVisibility
    public var presenceVisibility: SocialVisibility
    /// Hybrid follow consent (Slice 5): when true, new follows become requests.
    /// Decoded leniently so pre-Slice-5 cached profiles stay readable.
    public var requireFollowApproval: Bool
    /// Bitmask of DISABLED SocialPushType raw values (bit n = type n+1 off);
    /// 0 = every social push enabled (Slice 8). Lenient decode for old caches.
    public var socialPushDisabled: Int64
    /// Inverted discoverability (Slice 9): true removes this profile from
    /// people search and suggestions. Zero-value = discoverable.
    public var hideFromDiscovery: Bool
    public var curator: Bool

    private enum CodingKeys: String, CodingKey {
        case userId, handle, displayName, bio, avatarURL, createdAt, termsVersion
        case avatarVisibility, bioVisibility, followedShowsVisibility, topPodcastsVisibility
        case statsVisibility, historyVisibility, presenceVisibility, requireFollowApproval
        case socialPushDisabled
        case hideFromDiscovery
        case curator
    }

    // Swift-qualified: the SwiftProtobuf import has its own Decoder protocol.
    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        handle = try container.decode(String.self, forKey: .handle)
        displayName = try container.decode(String.self, forKey: .displayName)
        bio = try container.decode(String.self, forKey: .bio)
        avatarURL = try container.decode(String.self, forKey: .avatarURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        termsVersion = try container.decode(Int.self, forKey: .termsVersion)
        avatarVisibility = try container.decode(SocialVisibility.self, forKey: .avatarVisibility)
        bioVisibility = try container.decode(SocialVisibility.self, forKey: .bioVisibility)
        followedShowsVisibility = try container.decode(SocialVisibility.self, forKey: .followedShowsVisibility)
        topPodcastsVisibility = try container.decode(SocialVisibility.self, forKey: .topPodcastsVisibility)
        statsVisibility = try container.decode(SocialVisibility.self, forKey: .statsVisibility)
        historyVisibility = try container.decode(SocialVisibility.self, forKey: .historyVisibility)
        presenceVisibility = try container.decode(SocialVisibility.self, forKey: .presenceVisibility)
        requireFollowApproval = try container.decodeIfPresent(Bool.self, forKey: .requireFollowApproval) ?? false
        socialPushDisabled = try container.decodeIfPresent(Int64.self, forKey: .socialPushDisabled) ?? 0
        hideFromDiscovery = try container.decodeIfPresent(Bool.self, forKey: .hideFromDiscovery) ?? false
        curator = try container.decodeIfPresent(Bool.self, forKey: .curator) ?? false
    }

    public init(userId: String,
                handle: String,
                displayName: String,
                bio: String = "",
                avatarURL: String = "",
                createdAt: Date? = nil,
                termsVersion: Int = 0,
                avatarVisibility: SocialVisibility = .private,
                bioVisibility: SocialVisibility = .private,
                followedShowsVisibility: SocialVisibility = .private,
                topPodcastsVisibility: SocialVisibility = .private,
                statsVisibility: SocialVisibility = .private,
                historyVisibility: SocialVisibility = .private,
                presenceVisibility: SocialVisibility = .private,
                requireFollowApproval: Bool = false,
                socialPushDisabled: Int64 = 0,
                hideFromDiscovery: Bool = false, curator: Bool = false) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.bio = bio
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.termsVersion = termsVersion
        self.avatarVisibility = avatarVisibility
        self.bioVisibility = bioVisibility
        self.followedShowsVisibility = followedShowsVisibility
        self.topPodcastsVisibility = topPodcastsVisibility
        self.statsVisibility = statsVisibility
        self.historyVisibility = historyVisibility
        self.presenceVisibility = presenceVisibility
        self.requireFollowApproval = requireFollowApproval
        self.socialPushDisabled = socialPushDisabled
        self.hideFromDiscovery = hideFromDiscovery
        self.curator = curator
    }
}

/// Another user's profile as returned by the public read (`social/u/{handle}`).
/// The server has already applied per-field visibility and the viewer's block
/// relationship, so hidden fields arrive empty and a blocked/absent profile is
/// surfaced as a fetch miss. Mapped from `Api_PublicProfileResponse`.
public struct SocialPublicProfile: Equatable, Sendable {
    public let userId: String
    public let handle: String
    public let displayName: String
    public let bio: String       // empty when hidden from this viewer
    public let avatarURL: String // empty when hidden from this viewer
    public let createdAt: Date?
    public let hasStats: Bool
    public let curator: Bool

    public let followerCount: Int
    public let followingCount: Int
    public let yourFollowState: FollowState

    // Visibility-gated sections; empty/nil when hidden from this viewer.
    public let followedShows: [SocialProfilePodcast]
    public let topPodcasts: [SocialProfilePodcast]
    public let stats: SocialProfileStats?
    public let recentlyPlayed: [SocialProfileEpisode]
    public let lists: [SharedList]
    public let milestones: [SocialMilestone]

    public init(userId: String, handle: String, displayName: String, bio: String, avatarURL: String, createdAt: Date?, hasStats: Bool,
                curator: Bool = false,
                followerCount: Int = 0, followingCount: Int = 0, yourFollowState: FollowState = .none,
                followedShows: [SocialProfilePodcast] = [], topPodcasts: [SocialProfilePodcast] = [],
                stats: SocialProfileStats? = nil, recentlyPlayed: [SocialProfileEpisode] = [],
                lists: [SharedList] = [], milestones: [SocialMilestone] = []) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.bio = bio
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.hasStats = hasStats
        self.curator = curator
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.yourFollowState = yourFollowState
        self.followedShows = followedShows
        self.topPodcasts = topPodcasts
        self.stats = stats
        self.recentlyPlayed = recentlyPlayed
        self.lists = lists
        self.milestones = milestones
    }
}

/// A podcast entry in a public-profile section (followed shows / top podcasts).
public struct SocialProfilePodcast: Equatable, Sendable, Identifiable {
    public let uuid: String
    public let title: String
    public let author: String
    public let playedSeconds: Int64

    public var id: String { uuid }

    public init(uuid: String, title: String, author: String, playedSeconds: Int64 = 0) {
        self.uuid = uuid
        self.title = title
        self.author = author
        self.playedSeconds = playedSeconds
    }
}

/// A recently-played entry in a public-profile section.
public struct SocialProfileEpisode: Equatable, Sendable, Identifiable {
    public let uuid: String
    public let podcastUuid: String
    public let title: String
    public let playedAt: Date?

    public var id: String { uuid }

    public init(uuid: String, podcastUuid: String, title: String, playedAt: Date?) {
        self.uuid = uuid
        self.podcastUuid = podcastUuid
        self.title = title
        self.playedAt = playedAt
    }
}

/// Aggregate listening totals on a public profile (totals only — the per-day
/// heatmap series never leaves the device).
public struct SocialProfileStats: Equatable, Sendable {
    public let timeListenedSeconds: Int64
    public let listeningSince: Date?

    public init(timeListenedSeconds: Int64, listeningSince: Date?) {
        self.timeListenedSeconds = timeListenedSeconds
        self.listeningSince = listeningSince
    }
}

// MARK: - Wire mapping (internal: the Api_* types are module-internal)

extension SocialVisibility {
    init(_ api: Api_SocialVisibility) {
        switch api {
        case .public: self = .public
        case .followersOnly: self = .followersOnly
        case .private, .unspecified, .UNRECOGNIZED: self = .private
        }
    }

    var apiValue: Api_SocialVisibility {
        switch self {
        case .private: return .private
        case .public: return .public
        case .followersOnly: return .followersOnly
        }
    }
}

extension SocialProfile {
    init(_ api: Api_SocialProfile) {
        self.init(userId: api.userID,
                  handle: api.handle,
                  displayName: api.displayName,
                  bio: api.bio,
                  avatarURL: api.avatarURL,
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  termsVersion: Int(api.termsVersion),
                  avatarVisibility: SocialVisibility(api.avatarVisibility),
                  bioVisibility: SocialVisibility(api.bioVisibility),
                  followedShowsVisibility: SocialVisibility(api.followedShowsVisibility),
                  topPodcastsVisibility: SocialVisibility(api.topPodcastsVisibility),
                  statsVisibility: SocialVisibility(api.statsVisibility),
                  historyVisibility: SocialVisibility(api.historyVisibility),
                  presenceVisibility: SocialVisibility(api.presenceVisibility),
                  requireFollowApproval: api.requireFollowApproval,
                  socialPushDisabled: api.socialPushDisabled,
                  hideFromDiscovery: api.hideFromDiscovery, curator: api.curator)
    }
}

extension SocialPublicProfile {
    init(_ api: Api_PublicProfileResponse) {
        self.init(userId: api.userID,
                  handle: api.handle,
                  displayName: api.displayName,
                  bio: api.bio,
                  avatarURL: api.avatarURL,
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  hasStats: api.hasStats_p,
                  curator: api.curator,
                  followerCount: Int(api.followerCount),
                  followingCount: Int(api.followingCount),
                  yourFollowState: FollowState(api.yourFollowState),
                  followedShows: api.followedShows.map(SocialProfilePodcast.init),
                  topPodcasts: api.topPodcasts.map(SocialProfilePodcast.init),
                  stats: api.hasStats ? SocialProfileStats(api.stats) : nil,
                  recentlyPlayed: api.recentlyPlayed.map(SocialProfileEpisode.init),
                  lists: api.lists.map(SharedList.init),
                  milestones: api.milestones.compactMap(SocialMilestone.init))
    }
}

extension SocialProfilePodcast {
    init(_ api: Api_SocialProfilePodcast) {
        self.init(uuid: api.uuid, title: api.title, author: api.author, playedSeconds: api.playedSeconds)
    }
}

extension SocialProfileEpisode {
    init(_ api: Api_SocialProfileEpisode) {
        self.init(uuid: api.uuid, podcastUuid: api.podcastUuid, title: api.title,
                  playedAt: api.hasPlayedAt ? api.playedAt.date : nil)
    }
}

extension SocialProfileStats {
    init(_ api: Api_SocialProfileStats) {
        self.init(timeListenedSeconds: api.timeListenedSeconds,
                  listeningSince: api.hasListeningSince ? api.listeningSince.date : nil)
    }
}

/// A materialized listening-ladder crossing (Slice 14, ADR-0013). Shared
/// surfaces obey the owner's stats visibility; kind 1 = hours listened,
/// 2 = episodes finished.
public struct SocialMilestone: Equatable, Sendable, Identifiable {
    public enum Kind: Int, Sendable {
        case hours = 1
        case episodes = 2
    }

    public let kind: Kind
    public let tier: Int
    public let crossedAt: Date?

    public var id: String { "\(kind.rawValue)-\(tier)" }

    public init(kind: Kind, tier: Int, crossedAt: Date? = nil) {
        self.kind = kind
        self.tier = tier
        self.crossedAt = crossedAt
    }

    init?(_ api: Api_Milestone) {
        guard let kind = Kind(rawValue: Int(api.kind)) else { return nil }
        self.init(kind: kind, tier: Int(api.tier), crossedAt: api.hasCrossedAt ? api.crossedAt.date : nil)
    }
}
