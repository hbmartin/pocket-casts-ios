import Foundation
import SwiftProtobuf

/// A written podcast review: the author's star rating plus their attributed
/// public text (docs/Social.md Slice 3). Stars remain the anonymous
/// account-level primitive; the text half requires a joined account.
public struct PodcastReview: Equatable, Sendable, Identifiable {
    public let userId: String
    public let handle: String
    public let displayName: String
    public let rating: Int
    public let text: String
    public let createdAt: Date?
    public let updatedAt: Date?

    public var id: String { userId }

    public init(userId: String, handle: String, displayName: String, rating: Int, text: String, createdAt: Date?, updatedAt: Date?) {
        self.userId = userId.lowercased()
        self.handle = handle
        self.displayName = displayName
        self.rating = rating
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A page of reviews for a podcast, plus the caller's own review when present.
public struct PodcastReviewPage: Equatable, Sendable {
    public let reviews: [PodcastReview]
    public let total: Int
    public let yourReview: PodcastReview?

    public init(reviews: [PodcastReview], total: Int, yourReview: PodcastReview?) {
        self.reviews = reviews
        self.total = total
        self.yourReview = yourReview
    }
}

/// The fixed reaction set (❤️ 😂 🤯 👏 🔥) — mirrors the wire ReactionKind.
public enum ReactionKind: Int, Sendable, CaseIterable, Identifiable {
    case heart = 1
    case laugh = 2
    case mindBlown = 3
    case clap = 4
    case fire = 5

    public var id: Int { rawValue }

    public var emoji: String {
        switch self {
        case .heart: "❤️"
        case .laugh: "😂"
        case .mindBlown: "🤯"
        case .clap: "👏"
        case .fire: "🔥"
        }
    }
}

/// Aggregate reactions on an episode plus the caller's own (nil = none).
public struct EpisodeReactions: Equatable, Sendable {
    public let counts: [ReactionKind: Int]
    public let yourReaction: ReactionKind?

    public init(counts: [ReactionKind: Int], yourReaction: ReactionKind?) {
        self.counts = counts
        self.yourReaction = yourReaction
    }
}

// MARK: - Wire mapping (internal)

extension PodcastReview {
    init(_ api: Api_PodcastReview) {
        self.init(userId: api.userID,
                  handle: api.handle,
                  displayName: api.displayName,
                  rating: Int(api.rating),
                  text: api.text,
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  updatedAt: api.hasUpdatedAt ? api.updatedAt.date : nil)
    }
}

extension EpisodeReactions {
    init(_ api: Api_EpisodeReactionsResponse) {
        var counts: [ReactionKind: Int] = [:]
        for entry in api.counts {
            if let kind = ReactionKind(rawValue: entry.kind.rawValue) {
                counts[kind] = Int(entry.count)
            }
        }
        self.init(counts: counts, yourReaction: ReactionKind(rawValue: api.yourReaction.rawValue))
    }
}
