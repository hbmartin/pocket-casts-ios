import Foundation
import GRDB
import GRDBMacros

/// One appearance of an entity in an episode (migration 89, Highlights S10).
/// `canonicalKey` is the shared case- and diacritic-insensitive folding of the
/// display name — the same rule across all three sources, so a person credited
/// on one show, renamed as a speaker on another, and mentioned on a third
/// aggregates into one identity (the documented v1 name-key limitation).
@GRDBRecord(table: "MentionedEntity")
public struct MentionedEntityRecord: Equatable, Sendable {
    /// `nil` encodes as NULL on insert so SQLite assigns the AUTOINCREMENT primary key.
    public var id: Int64?
    public var kind = ""
    public var canonicalKey = ""
    public var displayName = ""
    public var episodeUuid = ""
    public var podcastUuid: String?
    /// Seek anchor for transcript mentions; nil for credits and speakers.
    public var startTime: Double?
    public var source = ""
    /// The feed credit's role (host/guest/…), when declared.
    public var role: String?
    public var createdAt: Double = 0

    public init() {}
}

/// The three places an entity appearance can come from.
public enum MentionedEntitySource: String, Sendable {
    case credit
    case speaker
    case mention
}

/// Mirror of the app-side entity kinds (stored as raw strings so the substrate
/// doesn't chase the generator's enum).
public enum MentionedEntityKind: String, CaseIterable, Sendable {
    case person, book, product, website, place, organization, other
}

/// A library-wide aggregate row: one entity with its reach.
public struct MentionedEntityAggregate: Sendable, Equatable {
    public let canonicalKey: String
    public let displayName: String
    public let kind: String
    public let episodeCount: Int
    public let podcastCount: Int

    public init(canonicalKey: String, displayName: String, kind: String, episodeCount: Int, podcastCount: Int) {
        self.canonicalKey = canonicalKey
        self.displayName = displayName
        self.kind = kind
        self.episodeCount = episodeCount
        self.podcastCount = podcastCount
    }
}
