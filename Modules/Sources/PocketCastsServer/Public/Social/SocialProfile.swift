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
                presenceVisibility: SocialVisibility = .private) {
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

    public init(userId: String, handle: String, displayName: String, bio: String, avatarURL: String, createdAt: Date?, hasStats: Bool) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.bio = bio
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.hasStats = hasStats
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
                  presenceVisibility: SocialVisibility(api.presenceVisibility))
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
                  hasStats: api.hasStats_p)
    }
}
