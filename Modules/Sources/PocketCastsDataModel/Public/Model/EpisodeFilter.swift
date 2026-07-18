import Foundation
import GRDB
import GRDBMacros

@GRDBRecord(table: "SJFilteredPlaylist")
public struct EpisodeFilter: Equatable, Hashable, Sendable {
    public var id = 0 as Int64
    public var autoDownloadEpisodes = false
    public var customIcon = 0 as Int32
    public var filterAllPodcasts = false
    public var filterAudioVideoType = 0 as Int32
    public var filterDownloaded = false
    @GRDBIgnore
    public let filterDownloading = true // we no longer let the user change this, it's just always true
    public var filterFinished = false
    public var filterNotDownloaded = false
    public var filterPartiallyPlayed = false
    public var filterStarred = false
    public var filterUnplayed = false
    public var filterHours = 0 as Int32
    public var playlistName = ""
    public var sortPosition = 0 as Int32
    public var sortType = 0 as Int32
    public var uuid = ""
    public var podcastUuids = ""
    public var autoDownloadLimit = 0 as Int32
    public var filterDuration = false
    public var longerThan = 0 as Int32
    public var shorterThan = 0 as Int32
    public var syncStatus = 0 as Int32
    public var wasDeleted = false
    public var manual: Bool = false
    public var showArchivedEpisodes: Bool = false
    public var playlistUpdateDate: Date?
    /// Custom playlists: the versioned JSON envelope (`CustomPlaylistQuery`) describing a
    /// builder AST or validated SQL WHERE fragment. `nil` = regular smart/manual playlist.
    /// Device-local: rows with a non-nil value are excluded from account sync and file sync.
    public var customQuery: String?

    /// Shared-list mirror link (Slice 7, ADR-0011): the server list this
    /// playlist mirrors, if any, and the account's role on it
    /// (0 = none, 1 = owner, 2 = collaborator, 3 = subscriber).
    public var sharedListId: Int64?
    public var sharedRole: Int32 = 0

    /// Whether this playlist is a custom (query-envelope) playlist. Computed, not persisted.
    /// `manual` wins over a stray envelope so manual playlists can never lose their
    /// episode-membership semantics.
    public var isCustom: Bool { customQuery != nil && !manual }

    // Internal tracking
    @GRDBIgnore
    public var isNew: Bool = false
    @GRDBIgnore
    public var podcastSmartRuleApplied: Bool = false
    @GRDBIgnore
    public var episodesSmartRuleApplied: Bool = false
    @GRDBIgnore
    public var releaseDateSmartRuleApplied: Bool = false
    @GRDBIgnore
    public var mediaTypeSmartRuleApplied: Bool = false
    @GRDBIgnore
    public var downloadStatusSmartRuleApplied: Bool = false

    public init() {}

    public mutating func setTitle(_ title: String?, defaultTitle: String) {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            playlistName = defaultTitle

            return
        }

        playlistName = title
    }

    public func markingAsPlayedRemovesItem() -> Bool {
        !filterFinished
    }

    public func markingAsUnplayedRemovesItem() -> Bool {
        !filterUnplayed
    }

    public func deletingFileRemovesItem() -> Bool {
        !filterDownloaded
    }

    public mutating func addPodcast(podcastUuid: String) {
        if podcastUuids.isEmpty {
            filterAllPodcasts = false
            podcastUuids = podcastUuid
        } else {
            podcastUuids.append(",\(podcastUuid)")
        }

        syncStatus = SyncStatus.notSynced.rawValue
    }

    public mutating func removePodcast(podcastUuid: String) {
        var podcasts = podcastUuids.components(separatedBy: ",")
        podcasts.removeAll(where: { uuid -> Bool in
            podcastUuid == uuid
        })

        if podcasts.isEmpty {
            filterAllPodcasts = true
            podcastUuids = ""
        } else {
            podcastUuids = podcasts.joined(separator: ",")
        }
    }

    // Equality and hashing are both keyed on `uuid` (the stable sync identity), preserving the semantics
    // the NSObject `isEqual`/`hash` carried after the uuid-consistency fix. Not synthesized (which would
    // compare every field): two rows with the same uuid are the same playlist regardless of local id or
    // transient tracking flags, and `Set<EpisodeFilter>` dedup relies on that.
    public static func == (lhs: EpisodeFilter, rhs: EpisodeFilter) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}
