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

    /// Enable on-device diarized transcription (speech-to-text with speaker labels)
    case diarizedTranscription

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

    /// Custom playlists: user-defined query playlists built either with the visual
    /// condition builder or a raw SQL WHERE fragment. Device-local (excluded from
    /// account sync and file sync).
    case customPlaylists

    /// Auth hardening workstream A: password accounts authenticate via rotating
    /// refresh tokens (refresh grant tried first, one-shot password-to-refresh-token
    /// migration) and stop persisting the account password in the Keychain.
    /// Default OFF until the M1 server contract (user/login and user/register
    /// issuing refresh tokens) is live; see plans/API Auth Hardening Plan.md.
    case refreshTokenForPasswordAuth

    /// Auth hardening workstream B: share-list creation authenticates with the
    /// user's bearer token instead of the legacy static SHA-1 signature.
    /// Default OFF until the sharing service dual-accept window is live;
    /// see plans/API Auth Hardening Plan.md.
    case sharingListBearerAuth

    /// AI summary card on the episode detail screen with tap-to-seek key
    /// takeaways (on-device FoundationModels with deterministic fallbacks);
    /// see plans/AI UX Improvements.md Phase 2.
    case episodeSummaries

    /// Smart highlights: bookmarks enriched with transcript excerpts and
    /// on-device auto-titles, shareable as quote cards;
    /// see plans/AI UX Improvements.md Phase 3.
    case smartHighlights

    /// Library-wide transcript search: viewed podcast-provided transcripts are
    /// FTS-indexed on device and surfaced as a Transcripts section in search;
    /// see plans/AI UX Improvements.md Phase 4.
    case transcriptSearch

    /// Prompted playlists: natural language description -> smart playlist draft
    /// (on-device FoundationModels with a deterministic rule-parser fallback);
    /// see plans/AI UX Improvements.md Phase 5.
    case promptedPlaylists

    /// People credits on episode detail (parsed from `<podcast:person>` for
    /// local feeds; server payloads documented in docs/ServerAPISurface.md);
    /// see plans/AI UX Improvements.md Phase 6.
    case episodeCredits

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
        case .diarizedTranscription:
            BuildEnvironment.current != .appStore
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
        case .customPlaylists:
            BuildEnvironment.current == .debug
        case .refreshTokenForPasswordAuth:
            false
        case .sharingListBearerAuth:
            false
        case .episodeSummaries:
            BuildEnvironment.current != .appStore
        case .smartHighlights:
            BuildEnvironment.current != .appStore
        case .transcriptSearch:
            BuildEnvironment.current != .appStore
        case .promptedPlaylists:
            BuildEnvironment.current != .appStore
        case .episodeCredits:
            BuildEnvironment.current != .appStore
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
