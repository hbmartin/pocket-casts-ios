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

    // Shows the searchbar in Listening History view
    case listeningHistorySearch

    /// Use the Mimetype library to check the file mimetype
    case useMimetypePackage

    /// Enable the Segmented Control into the Effects Player panel
    /// to apply the Global or local settings
    case customPlaybackSettings

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

    /// Use single update query to mark all episodes selected synced
    case markAllSyncedInSingleStatement

    /// Show Manage Downloaded episode banner/modal when running in low space in the device
    case manageDownloadedEpisodes

    /// Enable/Disable the podcast feed reload feature
    case podcastFeedUpdate

    /// Enable/Disable the use of a thread safe ongoing downloads cache
    case downloadsThreadSafeCache

    /// Enable Disable the use of suggested folders
    case suggestedFolders

    /// Enable the generated transcript
    case generatedTranscripts

    /// Enable synced transcripts with playback timing
    case syncedTranscripts

    /// Encourage Account Creation
    case encourageAccountCreation

    /// Avoid replace actions for Up Next episode queue when swapping the currently playing episode
    case avoidReplaceOnEpisodeSwap

    /// Enable the new podcast sorting options
    case podcastsSortChanges

    /// Recommendations including discover v3 support
    case recommendations

    /// When replacing an episode list with a new one, use the provided episode instead of Up Next Queue
    case replaceSpecificEpisode

    /// Shows transcript excerpt in episode detail
    case episodeDetailTranscript

    /// Improves configuration for the streaming requet download session
    case streamingCustomSessionConfiguration

    /// Enabled the attributed text view in the Data Usage warning Sheet
    case useDescriptiveActionAttributedTextView

    /// Retry failed downloads and stream without the user agent
    case retryWithoutUserAgent

    /// Whether to use database concurrent reads or not
    case concurrentDatabaseReads

    /// Limit playback position changes when switching episodes
    case limitPlaybackPositionChanges

    /// Use the new upgrade screens for account creation
    case newOnboardingAccountCreation

    /// Adds a sharing button to the transcript view
    case shareTranscripts

    /// Skips switching player to downloaded file if already playing from the same cached streamed file
    case doNotSwitchToDownloadedFile

    /// Use the new interests and recommendations flow
    case newOnboardingRecommendationChanges

    /// Use the new search endpoint and new UI
    case searchImprovements

    /// Use the new predictive endpoint and show predictions
    case searchPredictive

    /// Render Bookmarks inline in PodcastViewController using SwiftUI BookmarksListView
    case podcastBookmarksInline

    /// Enable localization headers
    case enableLocalizationHeaders

    /// Upgrades the Effects Player's AudioReadTask to a QOS level of "userInitiated" from "default"
    case effectsPlayerQOSUpgrade

    /// Uses the PlaylistMetadataLoader cache before running the query (the query will update when it's done)
    case playlistDataCacheBeforeQuery

    /// Ignores play remote commands when other audio is playing
    case ignorePlayWithOtherAudio

    /// activates the audio session in the background to avoid locks in the main thread
    case activateAudioSessionInBackground

    /// Use cellular-specific network APIs instead of expensive network APIs
    case useCellularNetworkApis
    /// Optimizes manual playlist queries with improved deduplication
    case optimizeManualPlaylistQueries

    /// Use a background queue for streaming callbacks
    case useBackgroundQueueForStreamingCallback

    /// Moves the shouldKeepPlaying after we check that the episode is over
    case checkFinishedTimeBeforeShouldKeepPlaying

    /// Activate audio session to enable multi-speaker selection in route picker
    case activateAudioSessionForRoutePicker

    /// Don't autoplay when route changes
    case dontAutoplayOnRouteChange

    /// Allow the release of the Media Exporter when is no longer being used by the player
    case releaseMediaExporterWhenNoLongerActive

    /// Enable VoiceBoostN with updated description copy (TestFlight only)
    case voiceBoostN

    /// Adds invalidation to the playlist cache on appearance when its been > 30 seconds
    case playlistCacheInvalidation

    /// Skip Up Next sync when protected data is unavailable to prevent sync with incorrect UserDefaults values
    case skipSyncWhenProtectedDataUnavailable

    /// Check if protected data is available before running migrations that touch keychain
    case checkProtectedDataBeforeMigration

    /// Ensure that tmp files are removed when no longer needed
    case cleanUpTmpFiles

    /// Display playback errors on player
    case displayErrorsOnPlayer

    /// Detect truncated background sync downloads by comparing received bytes to Content-Length
    case detectTruncatedBackgroundSyncDownloads

    /// Track network data usage per episode/connection type in the NetworkDataUsage table
    case trackNetworkDataUsage

    /// Show the listening activity heatmap on the Stats screen
    case statsHeatmap

    /// Show explicit content badges on podcasts
    case showExplicitBadges

    /// Enable the Share Profile feature
    case shareProfile

    /// Log database access performed on the main thread (DEBUG builds only)
    case logMainThreadDatabaseAccess

    /// Enable the Up Next sort button
    case upNextSort

    /// Enable Generated Chapters
    case generatedChapters

    /// Enable the local-first file sync engine and app integration
    case fileSync

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
        case .listeningHistorySearch:
            true
        case .useMimetypePackage:
            true
        case .customPlaybackSettings:
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
        case .markAllSyncedInSingleStatement:
            true
        case .manageDownloadedEpisodes:
            true
        case .podcastFeedUpdate:
            true
        case .downloadsThreadSafeCache:
            true
        case .suggestedFolders:
            true
        case .generatedTranscripts:
            true
        case .syncedTranscripts:
            true
        case .encourageAccountCreation:
            true
        case .avoidReplaceOnEpisodeSwap:
            true
        case .podcastsSortChanges:
            true
        case .recommendations:
            true
        case .replaceSpecificEpisode:
            true
        case .episodeDetailTranscript:
            true
        case .streamingCustomSessionConfiguration:
            true
        case .useDescriptiveActionAttributedTextView:
            true
        case .retryWithoutUserAgent:
            true
        case .concurrentDatabaseReads:
            true
        case .limitPlaybackPositionChanges:
            true
        case .newOnboardingAccountCreation:
            true
        case .shareTranscripts:
            true
        case .doNotSwitchToDownloadedFile:
            true
        case .newOnboardingRecommendationChanges:
            true
        case .searchImprovements:
            true
        case .searchPredictive:
            true
        case .podcastBookmarksInline:
            true
        case .enableLocalizationHeaders:
            true
        case .effectsPlayerQOSUpgrade:
            true
        case .playlistDataCacheBeforeQuery:
            true
        case .ignorePlayWithOtherAudio:
            true
        case .activateAudioSessionInBackground:
            true
        case .useCellularNetworkApis:
            true
        case .optimizeManualPlaylistQueries:
            true
        case .useBackgroundQueueForStreamingCallback:
            true
        case .checkFinishedTimeBeforeShouldKeepPlaying:
            true
        case .activateAudioSessionForRoutePicker:
            true
        case .dontAutoplayOnRouteChange:
            true
        case .releaseMediaExporterWhenNoLongerActive:
            true
        case .voiceBoostN:
            false
        case .playlistCacheInvalidation:
            true
        case .skipSyncWhenProtectedDataUnavailable:
            true
        case .checkProtectedDataBeforeMigration:
            true
        case .cleanUpTmpFiles:
            true
        case .displayErrorsOnPlayer:
            true
        case .detectTruncatedBackgroundSyncDownloads:
            true
        case .trackNetworkDataUsage:
            true
        case .statsHeatmap:
            true
        case .showExplicitBadges:
            false
        case .shareProfile:
            BuildEnvironment.current == .debug
        case .logMainThreadDatabaseAccess:
            true
        case .upNextSort:
            BuildEnvironment.current == .debug
        case .generatedChapters:
            BuildEnvironment.current == .debug
        case .fileSync:
            BuildEnvironment.current == .debug
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

    private static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
}
