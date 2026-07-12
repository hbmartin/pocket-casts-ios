import Foundation

public enum FeatureFlag: String, CaseIterable, Sendable {

    /// Whether logging of analytics events in console are enabled
    case analyticsLogging

    /// Whether logging the theme properties in analytics events
    case appThemePropertiesLogging

    /// Store settings as JSON in User Defaults (global) or SQLite (podcast)
    case newSettingsStorage

    /// Syncing all app and podcast settings
    case settingsSync

    /// When a user sign in, we always mark ALL podcasts as unsynced
    /// This recently caused issues, syncing changes that shouldn't have been synced
    /// When `true`, we only mark podcasts as unsynced if the user never signed in before
    case onlyMarkPodcastsUnsyncedForNewUsers

    /// Run a vacuum process on the database in order to optimize data fetch
    case runVacuumOnVersionUpdate

    /// Push two auto downloads on subscribe of a podcast
    case autoDownloadOnSubscribe

    /// Replace Subscribe/Unsubscribe with Follow/Unfollow
    case useFollowNaming

    /// Enable/Disable the podcast feed reload feature
    case podcastFeedUpdate

    /// Enable the generated transcript
    case generatedTranscripts

    /// Enable synced transcripts with playback timing
    case syncedTranscripts

    /// Enable the new podcast sorting options
    case podcastsSortChanges

    /// Use the new upgrade screens for account creation
    case newOnboardingAccountCreation

    /// Use the new search endpoint and new UI
    case searchImprovements

    /// Optimizes manual playlist queries with improved deduplication
    case optimizeManualPlaylistQueries

    /// Show explicit content badges on podcasts
    case showExplicitBadges

    public var enabled: Bool {
        if let overriddenValue = FeatureFlagOverrideStore().overriddenValue(for: self) {
            return overriddenValue
        }

        if let remoteValue = FeatureFlagRemoteConfigStore().overriddenValue(for: self) {
            return remoteValue
        }

        return `default`
    }

    public var `default`: Bool {
        switch self {
        case .analyticsLogging:
            false
        case .appThemePropertiesLogging:
            if BuildEnvironment.current == .debug {
                false
            } else {
                true
            }
        case .newSettingsStorage:
            shouldEnableSyncedSettings
        case .settingsSync:
            shouldEnableSyncedSettings
        case .onlyMarkPodcastsUnsyncedForNewUsers:
            true
        case .runVacuumOnVersionUpdate:
            false
        case .autoDownloadOnSubscribe:
            true
        case .useFollowNaming:
            true
        case .podcastFeedUpdate:
            true
        case .generatedTranscripts:
            true
        case .syncedTranscripts:
            true
        case .podcastsSortChanges:
            true
        case .newOnboardingAccountCreation:
            true
        case .searchImprovements:
            true
        case .optimizeManualPlaylistQueries:
            true
        case .showExplicitBadges:
            false
        }
    }

    /// A6a: flipped on 2026-07-12 after the storage/sync plumbing soak-tested behind
    /// the gate. The remote keys `new_settings_storage`/`settings_sync` are now live
    /// kill switches; A6b (deleting both flags and collapsing the ~158 call sites)
    /// follows after one release of soak — see docs/DeferredWork.md.
    private var shouldEnableSyncedSettings: Bool {
        true
    }

    /// Remote feature flag key used by runtime configuration providers.
    public var remoteKey: String? {
        switch self {
        case .newSettingsStorage:
            shouldEnableSyncedSettings ? "new_settings_storage" : nil
        case .settingsSync:
            shouldEnableSyncedSettings ? "settings_sync" : nil
        default:
            rawValue.lowerSnakeCased()
        }
    }
}

public struct FeatureFlagRemoteConfigStore {
    private let values: RemoteConfigValueStore

    public init(store: UserDefaults = .standard) {
        values = RemoteConfigValueStore(store: store)
    }

    public func overriddenValue(for flag: FeatureFlag) -> Bool? {
        guard let remoteKey = flag.remoteKey else {
            return nil
        }

        return values.bool(forKey: remoteKey)
    }
}

extension FeatureFlag: OverrideableFlag {
    public var description: String {
        rawValue
    }

    public var canOverride: Bool {
        true
    }
}
