import Foundation

// @unchecked Sendable: mutable model object passed across threads by long-standing
// convention in this codebase; consistency is maintained by database-write discipline
// rather than by the type itself.
public final class PlaylistEpisode: Equatable, Hashable, @unchecked Sendable {
    public var id = 0 as Int64
    public var episodePosition = 0 as Int32
    public var episodeUuid = ""
    public var title = ""
    public var podcastUuid = ""

    public init() {}

    public func taggableId() -> Int {
        Int(truncatingIfNeeded: id)
    }

    public static func == (lhs: PlaylistEpisode, rhs: PlaylistEpisode) -> Bool {
        lhs.episodeUuid == rhs.episodeUuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(episodeUuid)
    }
}
