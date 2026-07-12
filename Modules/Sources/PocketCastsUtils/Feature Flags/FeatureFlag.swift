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

    /// Enable the AVExportSession parallel download of any playing episode
    case streamAndCachePlayingEpisode

    /// When enabled it updates the code on filter callback to use a safer method to convert unmanaged player references.
    case defaultPlayerFilterCallbackFix

    /// When a user sign in, we always mark ALL podcasts as unsynced
    /// This recently caused issues, syncing changes that shouldn't have been synced
    /// When `true`, we only mark podcasts as unsynced if the user never signed in before
    case onlyMarkPodcastsUnsyncedForNewUsers

    /// Only update an episode if it fails playing
    /// If set to `false`, it will use the previous mechanism that always update
    /// but can lead to a bigger time between tapping play and actually playing it
    case whenPlayingOnlyUpdateEpisodeIfPlaybackFails

    /// When enabled, we ignore audio interruptions with InterruptionReason set to routeDisconnected
    /// (introduced in iOS 17) because these are not really interruptions as we have
    /// implemented them previously. If the route is disconnected, audio stops indefinitely
    /// until a new route connects (for which we'll received a different notification and handle accordingly)
    /// See: https://github.com/Automattic/pocket-casts-ios/issues/2049
    case ignoreRouteDisconnectedInterruption

    /// Uses the `isReadyToPlay` function to decide what logic to use when skipping.
    /// There's some scenario when the Default player switched to the Effects player when the stream is paused.
    /// This makes the skip unusable as the player doesn't have its task set yet.
    /// If the player is not ready to play, we should use the same logic we use when the player doesn't exist yet.
    case playerIsReadyToPlay

    /// Run a vacuum process on the database in order to optimize data fetch
    case runVacuumOnVersionUpdate

    /// Enable the Up Next shuffle button
    case upNextShuffle

    /// Push two auto downloads on subscribe of a podcast
    case autoDownloadOnSubscribe

    /// Replace Subscribe/Unsubscribe with Follow/Unfollow
    case useFollowNaming

    /// Use a cookie to manage `MTAudioProcessingTap` deallocation
    case useDefaultPlayerTapCookie

    /// Enable/Disable the podcast feed reload feature
    case podcastFeedUpdate

    /// Enable the generated transcript
    case generatedTranscripts

    /// Enable synced transcripts with playback timing
    case syncedTranscripts

    /// Avoid replace actions for Up Next episode queue when swapping the currently playing episode
    case avoidReplaceOnEpisodeSwap

    /// Enable the new podcast sorting options
    case podcastsSortChanges

    /// When replacing an episode list with a new one, use the provided episode instead of Up Next Queue
    case replaceSpecificEpisode

    /// Limit playback position changes when switching episodes
    case limitPlaybackPositionChanges

    /// Use the new upgrade screens for account creation
    case newOnboardingAccountCreation

    /// Skips switching player to downloaded file if already playing from the same cached streamed file
    case doNotSwitchToDownloadedFile

    /// Use the new search endpoint and new UI
    case searchImprovements

    /// Upgrades the Effects Player's AudioReadTask to a QOS level of "userInitiated" from "default"
    case effectsPlayerQOSUpgrade

    /// Ignores play remote commands when other audio is playing
    case ignorePlayWithOtherAudio

    /// activates the audio session in the background to avoid locks in the main thread
    case activateAudioSessionInBackground

    /// Optimizes manual playlist queries with improved deduplication
    case optimizeManualPlaylistQueries

    /// Moves the shouldKeepPlaying after we check that the episode is over
    case checkFinishedTimeBeforeShouldKeepPlaying

    /// Don't autoplay when route changes
    case dontAutoplayOnRouteChange

    /// Track network data usage per episode/connection type in the NetworkDataUsage table
    case trackNetworkDataUsage

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
        case .streamAndCachePlayingEpisode:
            true
        case .defaultPlayerFilterCallbackFix:
            true
        case .onlyMarkPodcastsUnsyncedForNewUsers:
            true
        case .whenPlayingOnlyUpdateEpisodeIfPlaybackFails:
            true
        case .ignoreRouteDisconnectedInterruption:
            true
        case .playerIsReadyToPlay:
            true
        case .runVacuumOnVersionUpdate:
            false
        case .upNextShuffle:
            true
        case .autoDownloadOnSubscribe:
            true
        case .useFollowNaming:
            true
        case .useDefaultPlayerTapCookie:
            true
        case .podcastFeedUpdate:
            true
        case .generatedTranscripts:
            true
        case .syncedTranscripts:
            true
        case .avoidReplaceOnEpisodeSwap:
            true
        case .podcastsSortChanges:
            true
        case .replaceSpecificEpisode:
            true
        case .limitPlaybackPositionChanges:
            true
        case .newOnboardingAccountCreation:
            true
        case .doNotSwitchToDownloadedFile:
            true
        case .searchImprovements:
            true
        case .effectsPlayerQOSUpgrade:
            true
        case .ignorePlayWithOtherAudio:
            true
        case .activateAudioSessionInBackground:
            true
        case .optimizeManualPlaylistQueries:
            true
        case .checkFinishedTimeBeforeShouldKeepPlaying:
            true
        case .dontAutoplayOnRouteChange:
            true
        case .trackNetworkDataUsage:
            true
        case .showExplicitBadges:
            false
        }
    }

    private var shouldEnableSyncedSettings: Bool {
        false
    }

    /// Remote feature flag key used by runtime configuration providers.
    public var remoteKey: String? {
        switch self {
        case .newSettingsStorage:
            shouldEnableSyncedSettings ? "new_settings_storage" : nil
        case .settingsSync:
            shouldEnableSyncedSettings ? "settings_sync" : nil
        case .defaultPlayerFilterCallbackFix:
            "default_player_filter_callback_fix"
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
