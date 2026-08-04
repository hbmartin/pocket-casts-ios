import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

@GRDBRecord(table: "SJPodcast")
// Value-type record (GRDB-7 north star). Sendable is honest: a copy crosses task
// boundaries by value, and write consistency is maintained on the DataManager write
// path. Equality/hashing key on `uuid` (see below), matching the prior NSObject
// `isEqual`/`hash` semantics callers rely on (e.g. `Set<Podcast>`).
public struct Podcast: Identifiable, Equatable, Hashable, Sendable {
    public var id = 0 as Int64
    public var addedDate: Date?
    public var autoDownloadSetting = 0 as Int32
    public var autoAddToUpNext = 0 as Int32
    @GRDBColumn("episodeKeepSetting")
    public var autoArchiveEpisodeLimit = 0 as Int32
    public var backgroundColor: String?
    public var detailColor: String? // dark artwork overlay
    public var primaryColor: String? // light tint
    public var secondaryColor: String? // dark tint
    public var lastColorDownloadDate: Date?
    public var imageURL: String?
    public var latestEpisodeUuid: String?
    public var latestEpisodeDate: Date?
    public var mediaType: String?
    public var lastThumbnailDownloadDate: Date?
    public var thumbnailStatus = 1 as Int32
    public var podcastUrl: String?
    public var author: String?
    public var overrideGlobalEffects = false
    public var playbackSpeed = 1 as Double
    public var boostVolume = false
    public var trimSilenceAmount = 0 as Int32
    public var podcastCategory: String?
    public var podcastDescription: String?
    public var podcastHTMLDescription: String?
    public var sortOrder = 0 as Int32
    public var startFrom = 0 as Int32
    public var skipLast = 0 as Int32
    public var subscribed = 1 as Int32
    public var title: String?
    public var uuid = ""
    public var syncStatus = 0 as Int32
    public var colorVersion = 1 as Int32
    public var pushEnabled = false
    public var episodeSortOrder = 1 as Int32
    public var episodeGrouping = 0 as Int32
    public var showType: String?
    public var estimatedNextEpisode: Date?
    public var episodeFrequency: String?
    public var lastUpdatedAt: String?
    public var excludeFromAutoArchive = false // we no longer use this setting, but it's here for migrations, etc
    public var overrideGlobalArchive = false
    public var autoArchivePlayedAfter = 0 as Double
    public var autoArchiveInactiveAfter = 0 as Double
    public var isPaid = false
    public var licensing = 0 as Int32
    public var fullSyncLastSyncAt: String?
    public var showArchived = false
    public var refreshAvailable = false
    public var folderUuid: String?
    public var usedCustomEffectsBefore = false
    public var isPrivate = false
    public var isExplicit = false
    public var fundingURL: String?

    @GRDBIgnore
    public var settings = PodcastSettings.defaults

    // transient not saved to database
    @GRDBIgnore
    public var cachedUnreadCount = 0

    // if set to an episode UUID, all podcast episodes after the given
    // UUID will be updated
    @GRDBIgnore
    public var forceRefreshEpisodeFrom: String? = nil

    public init() {}

    public func autoDownloadOn() -> Bool {
        autoDownloadSetting == AutoDownloadSetting.latest.rawValue
    }

    public func autoAddToUpNextOn() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return settings.addToUpNext
        } else {
            return autoAddToUpNext == AutoAddToUpNextSetting.addLast.rawValue || autoAddToUpNext == AutoAddToUpNextSetting.addFirst.rawValue
        }
    }

    public func autoAddToUpNextSetting() -> AutoAddToUpNextSetting? {
        if FeatureFlag.newSettingsStorage.enabled {
            if settings.addToUpNext {
                switch settings.addToUpNextPosition {
                case .top:
                    return .addFirst
                case .bottom:
                    return .addLast
                }
            } else {
                return .off
            }
        } else {
            return AutoAddToUpNextSetting(rawValue: autoAddToUpNext)
        }
    }

    public mutating func setAutoAddToUpNext(setting: AutoAddToUpNextSetting) {
        if FeatureFlag.newSettingsStorage.enabled {
            settings.addToUpNext = setting != .off
            settings.addToUpNextPosition = setting == .addFirst ? .top : .bottom
        }
        autoAddToUpNext = setting.rawValue
    }

    public func latestEpisode() -> Episode? {
        DataManager.sharedManager.findLatestEpisode(podcast: self)
    }

    public func latestEpisodes(limit: Int = 1) -> [Episode] {
        DataManager.sharedManager.findLatestEpisodes(podcast: self, limit: limit)
    }

    public func isSubscribed() -> Bool {
        subscribed != 0
    }

    // Identity is the persisted `uuid` (was NSObject `isEqual`/`hash`). Keyed on uuid only —
    // NOT memberwise — so two podcasts with the same uuid but differing transient/row fields
    // (e.g. an unsaved id == 0 copy vs the saved row) remain equal and hash equally, preserving
    // the prior class semantics and the `Set<Podcast>` dedup behaviour.
    public static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    public static func previewPodcast() -> Podcast {
        var podcast = Podcast()
        podcast.title = "The Greatest Podcast In The History Of Podcasts"
        podcast.author = "John Citizen Network Productions"
        podcast.uuid = "8a778760-a1de-0138-e66a-0acc26574db2"

        return podcast
    }
}

public enum TrimSilenceAmount: Int32, Codable, CaseIterable {
    case off = 0, low = 3, medium = 5, high = 10
}

extension TrimSilence {
    public init(amount: TrimSilenceAmount) {
        switch amount {
        case .off:
            self = .off
        case .low:
            self = .mild
        case .medium:
            self = .medium
        case .high:
            self = .madMax
        }
    }

    public var amount: TrimSilenceAmount {
        switch self {
        case .off:
            return .off
        case .mild:
            return .low
        case .medium:
            return .medium
        case .madMax:
            return .high
        }
    }
}

extension Podcast: CustomDebugStringConvertible {
    public var debugDescription: String {
        "Podcast: \(uuid) - \(title ?? "missing title")"
    }
}
