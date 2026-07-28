import Foundation

/// A snapshot of an episode's position in Up Next.
public struct PlaylistEpisode: Equatable, Hashable, Sendable {
    public var id: Int64
    public var episodePosition: Int32
    public var episodeUuid: String
    public var title: String
    public var podcastUuid: String

    /// Creates an Up Next snapshot. An `id` of zero requests a generated database ID when saved.
    public init(
        id: Int64 = 0,
        episodePosition: Int32 = 0,
        episodeUuid: String = "",
        title: String = "",
        podcastUuid: String = ""
    ) {
        self.id = id
        self.episodePosition = episodePosition
        self.episodeUuid = episodeUuid
        self.title = title
        self.podcastUuid = podcastUuid
    }

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
