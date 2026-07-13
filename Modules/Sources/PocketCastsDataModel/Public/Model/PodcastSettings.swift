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

    /// Per-podcast opt-OUT of remote/API transcription: when true, this show's automatic
    /// transcription jobs use the on-device engines even while a remote provider is configured
    /// globally. Device-local behavior (never synced to the server). Must stay a `false`-default
    /// Bool: payloads written before this field existed decode via the module-scoped
    /// `KeyedDecodingContainer` overload below (missing key → `false`).
    @ModifiedDate public var disableRemoteTranscription: Bool = false

    public static var defaults: Self {
        return PodcastSettings(trimSilence: .off, boostVolume: false, playbackSpeed: 1)
    }
}

/// Missing-key rescue for `@ModifiedDate` Bool fields added to `PodcastSettings` after payloads
/// already existed on disk: the synthesized `init(from:)` picks this more specific overload, so a
/// missing key decodes as `false` instead of throwing `keyNotFound` — which would discard the
/// podcast's ENTIRE settings payload (`Podcast.from` falls back to `PodcastSettings.defaults` on
/// any decode error). Companion to the `ModifiedDate<T?>` overload in `ModifiedDate.swift`.
///
/// Deliberately internal (module-scoped): every `ModifiedDate<Bool>` field in this module defaults
/// to `false`, so the fallback is always correct here. Other modules (e.g. `AppSettings` in
/// PocketCastsServer) have `true`-default Bool fields and must not inherit this behavior — and a
/// future `PodcastSettings` Bool defaulting to `true` must NOT rely on this overload.
extension KeyedDecodingContainer {
    func decode(_ type: ModifiedDate<Bool>.Type, forKey key: Key) throws -> ModifiedDate<Bool> {
        try decodeIfPresent(type, forKey: key) ?? ModifiedDate(wrappedValue: false)
    }
}
