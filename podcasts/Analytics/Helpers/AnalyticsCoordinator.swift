import Dependencies
import Foundation
import Synchronization
import UIKit
import PocketCastsDataModel
import PocketCastsUtils

@MainActor
protocol AnalyticsSourceProvider {
    /// Used to define the source view for the various analytics actions
    var analyticsSource: AnalyticsSource { get }
}

enum AnalyticsSource: String, AnalyticsDescribable {
    case appIconMenu = "app_icon_menu"
    case autoAdd = "auto_add"
    case autoDownloadSettings = "auto_download_settings"
    case chooseFolder = "choose_folder"
    case discover
    case discoverCategory = "discover_category"
    case discoverEpisodeList = "discover_episode_list"
    case discoverRankedList = "discover_ranked_list"
    case downloads
    case downloadStatus = "download_status"
    case episodeDetail = "episode_detail"
    case episodeStatus = "episode_status"
    case episodeTranscript = "episode_transcript"
    case episode
    case files
    case filters
    case folder
    case incomingShareList = "incoming_share_list"
    case listeningHistory = "listening_history"
    case mediaType = "media_type"
    case miniplayer
    case noFiles = "no_files"
    case noFilters = "no_filters"
    case notifications
    case nowPlayingWidget = "now_playing_widget"
    case onboarding
    case player
    case playerPlaybackEffects = "player_playback_effects"
    case playerSkipForwardLongPress = "player_skip_forward_long_press"
    case podcastScreen = "podcast_screen"
    case podcastScreenYouMightLike = "podcast_screen_you_might_like"
    case podcastSettings = "podcast_settings"
    case podcastsList = "podcasts_list"
    case profile
    case releaseDate = "release_date"
    case siri
    case starred
    case sync
    case upNext = "up_next"
    case userEpisode = "user_episode"
    case videoPlayerSkipForwardLongPress = "video_player_skip_forward_long_press"
    case playbackFailed = "playback_failed"
    case bookmark
    case interactiveWidget = "interactive_widget"
    case multiSelect = "multi_select"
    case episodeSwipeAction = "episode_swipe_action"
    case handleUserActivity = "handle_user_activity"
    case suggestedFolderPopup = "popup"
    case recommendations
    case playlistEditor = "playlist_editor"
    case unknown

    var analyticsDescription: String { rawValue }
}

/// Events fire from any thread; the one-shot source hint is lock-guarded.
// This type is non-final (production and test subclasses), so a checked
// @unchecked Sendable: non-final subclasses restate conformance; own state is guarded by Mutex.
nonisolated class AnalyticsCoordinator: @unchecked Sendable {
    /// Sometimes the playback source can't be inferred, just inform it here
    var currentSource: AnalyticsSource? {
        get { currentSourceState.withLock { $0 } }
        set { currentSourceState.withLock { $0 = newValue } }
    }

    private let currentSourceState = Mutex<AnalyticsSource?>(nil)

    private var currentEpisodeIsVideo: Bool {
        @Dependency(\.playbackManager) var playbackManager
        // Analytics events can originate off-main; bridge to the main-actor PlaybackManager
        if Thread.isMainThread {
            return MainActor.assumeIsolated { playbackManager.currentEpisode()?.videoPodcast() ?? false }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { playbackManager.currentEpisode()?.videoPodcast() ?? false }
            }
        }
    }

    var currentAnalyticsSource: AnalyticsSource {
        // Atomic take, so a source set concurrently between the read and the
        // reset can't be clobbered.
        let takenSource = currentSourceState.withLock { source in
            defer { source = nil }
            return source
        }
        if let takenSource {
            return takenSource
        }

        #if !APPCLIP
        // Walking the view-controller hierarchy is main-actor work; analytics
        // events can originate off-main, so bridge synchronously when needed
        if Thread.isMainThread {
            return MainActor.assumeIsolated { topAnalyticsSourceProvider()?.analyticsSource } ?? .unknown
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { topAnalyticsSourceProvider()?.analyticsSource } ?? .unknown
            }
        }
        #else
        return .unknown
        #endif
    }

    #if !APPCLIP
    func track(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        // Only dispatch async on the main thread if needed
        guard Thread.isMainThread else {
            let boxed = PocketCastsUtils.UncheckedSendable(properties)
            DispatchQueue.main.async {
                self.track(event, properties: boxed.value)
            }
            return
        }

        // Default keys win, matching the original merging behaviour; values are
        // strings/numbers/AnalyticsDescribable in practice, with a string fallback
        var mergedProperties: [String: any Sendable] = ["source": currentAnalyticsSource, "content_type": currentEpisodeIsVideo ? "video" : "audio"]
        for (key, value) in properties ?? [:] where mergedProperties[key] == nil {
            switch value {
            case let v as String: mergedProperties[key] = v
            case let v as Int: mergedProperties[key] = v
            case let v as Double: mergedProperties[key] = v
            case let v as Bool: mergedProperties[key] = v
            case let v as AnalyticsDescribable: mergedProperties[key] = v.analyticsDescription
            default: mergedProperties[key] = String(describing: value)
            }
        }
        Analytics.track(event, properties: mergedProperties)
    }

    @MainActor
    func getTopViewController(base: UIViewController? = SceneHelper.rootViewController()) -> UIViewController? {
        guard UIApplication.shared.applicationState == .active else {
            return nil
        }

        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)
        } else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return base
    }

    @MainActor
    func topAnalyticsSourceProvider() -> AnalyticsSourceProvider? {
        guard let topViewController = getTopViewController() else { return nil }

        var candidate: UIViewController? = topViewController
        while let viewController = candidate {
            if let provider = viewController as? AnalyticsSourceProvider {
                return provider
            }
            candidate = viewController.parent ?? viewController.presentingViewController
        }

        return nil
    }
    #else
    /// NOOP track event to preventing needing to wrap all the events in #if checks
    func track(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {}
    #endif
}
