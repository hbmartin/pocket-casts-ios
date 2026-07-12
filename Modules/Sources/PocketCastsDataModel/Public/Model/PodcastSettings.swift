import PocketCastsUtils

public struct PodcastSettings: JSONCodable, Equatable, Sendable {
    @ModifiedDate public var customEffects: Bool = false

    @ModifiedDate public var autoStartFrom: Int32 = 0
    @ModifiedDate public var autoSkipLast: Int32 = 0

    // Playback Effects
    @ModifiedDate public var trimSilence: TrimSilence
    @ModifiedDate public var boostVolume: Bool
    @ModifiedDate public var playbackSpeed: Double

    @ModifiedDate public var notification: Bool = false

    // Auto Archive
    @ModifiedDate public var autoArchive: Bool = false
    @ModifiedDate public var autoArchivePlayed: AutoArchiveAfterPlayed = .afterPlaying
    @ModifiedDate public var autoArchiveInactive: AutoArchiveAfterInactive = .never
    @ModifiedDate public var autoArchiveEpisodeLimit: Int32 = 0

    @ModifiedDate public var addToUpNext: Bool = false
    @ModifiedDate public var addToUpNextPosition: UpNextPosition = .bottom

    @ModifiedDate public var episodesSortOrder: PodcastEpisodeSortOrder = .newestToOldest
    @ModifiedDate public var episodeGrouping: PodcastGrouping = .none
    @ModifiedDate public var showArchived: Bool = false

    /// Chapter smart skip: case-insensitive title substrings whose matching chapters auto-deselect.
    /// Optional with a nil default so settings payloads written before this field existed still decode
    /// (see the `KeyedDecodingContainer` overload in `ModifiedDate.swift`).
    @ModifiedDate public var skipChapterTitles: [String]? = nil

    public static var defaults: Self {
        return PodcastSettings(trimSilence: .off, boostVolume: false, playbackSpeed: 1)
    }
}
