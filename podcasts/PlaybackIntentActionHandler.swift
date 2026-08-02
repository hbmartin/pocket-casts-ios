import AppIntents
import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import WidgetKit

/// Abstracts the playback + data operations the intent handler needs, so the
/// handler logic can be unit-tested with a fake. The live implementation drives
/// `PlaybackManager`/`DataManager`, matching the behaviour previously provided
/// by the removed SiriKit shortcuts stack.
nonisolated protocol PlaybackFacade: Sendable {
    func isPlaying() -> Bool
    func hasCurrentEpisode() -> Bool
    func isSleepTimerActive() -> Bool
    func upNextCount() -> Int
    func play()
    func pause()
    func playPause()
    func skipBack()
    func skipForward()
    func skipToNextChapter()
    func skipToPreviousChapter()
    func removeCurrentEpisodeFromUpNext()
    /// Async because the episode may need fetching first — the result must
    /// reflect whether playback actually started, not whether a fetch began.
    func loadSuggestedEpisode() async -> Bool
    func loadTopEpisode(forFilterUuid uuid: String) -> Bool
    func playAllEpisodes(forFilterUuid uuid: String) -> Bool
    func loadTopEpisode(forPodcastUuid uuid: String) -> Bool
    func setSleepTimer(seconds: TimeInterval)
    func extendSleepTimer(bySeconds seconds: TimeInterval)
    /// Saves a highlight at the current position; false when nothing is playing.
    func saveHighlight(source: BookmarkAnalyticsSource) -> Bool
    func refreshWidgets()
}

/// Single implementation path for playback actions triggered by App Intents,
/// WidgetKit controls and App Shortcuts. Runs in the app process where
/// `PlaybackManager` is available.
nonisolated struct PlaybackIntentActionHandler {
    static let shared = PlaybackIntentActionHandler()

    private let facade: PlaybackFacade

    init(facade: PlaybackFacade = LivePlaybackFacade()) {
        self.facade = facade
    }

    // MARK: WidgetKit controls

    func perform(_ action: PlaybackControlAction) {
        switch action {
        case .playPause:
            facade.playPause()
        case .skipBack:
            facade.skipBack()
        case .skipForward:
            facade.skipForward()
        case .nextChapter:
            facade.skipToNextChapter()
        case .playUpNext:
            // Only act when something is queued — mirrors playUpNext() below.
            if facade.hasCurrentEpisode(), facade.upNextCount() > 0 {
                facade.removeCurrentEpisodeFromUpNext()
            }
        case .sleepTimer:
            if facade.isSleepTimerActive() {
                facade.extendSleepTimer(bySeconds: Self.sleepTimerStepSeconds)
            } else {
                facade.setSleepTimer(seconds: Self.sleepTimerStepSeconds)
            }
        case .saveHighlight:
            _ = facade.saveHighlight(source: .control)
        }
        facade.refreshWidgets()
    }

    // MARK: Save Highlight (Highlights program S3)

    /// Backs `SaveHighlightIntent`; false (→ intent error dialog) when nothing
    /// is playing.
    @discardableResult
    func saveHighlight() -> Bool {
        facade.saveHighlight(source: .intent)
    }

    /// The Control Center sleep-timer button has no duration parameter: it
    /// starts (or extends by) this much.
    static let sleepTimerStepSeconds: TimeInterval = 15 * 60

    // MARK: Shortcut / App Intent actions

    @discardableResult
    func resume() -> Bool {
        guard facade.hasCurrentEpisode() else { return false }
        facade.play()
        facade.refreshWidgets()
        return true
    }

    func pausePlayback() {
        facade.pause()
        facade.refreshWidgets()
    }

    @discardableResult
    func playUpNext() -> Bool {
        // Mirrors the legacy Siri shortcut behaviour: the intent is to drop the
        // current episode and advance, so only act when there is something queued.
        guard facade.hasCurrentEpisode(), facade.upNextCount() > 0 else { return false }
        facade.removeCurrentEpisodeFromUpNext()
        facade.refreshWidgets()
        return true
    }

    @discardableResult
    func playSuggested() async -> Bool {
        let didLoad = await facade.loadSuggestedEpisode()
        if didLoad { facade.refreshWidgets() }
        return didLoad
    }

    @discardableResult
    func playPodcast(uuid: String) -> Bool {
        let didLoad = facade.loadTopEpisode(forPodcastUuid: uuid)
        if didLoad { facade.refreshWidgets() }
        return didLoad
    }

    @discardableResult
    func playFilter(uuid: String) -> Bool {
        let didLoad = facade.loadTopEpisode(forFilterUuid: uuid)
        if didLoad { facade.refreshWidgets() }
        return didLoad
    }

    @discardableResult
    func playAllFilter(uuid: String) -> Bool {
        let didStart = facade.playAllEpisodes(forFilterUuid: uuid)
        if didStart { facade.refreshWidgets() }
        return didStart
    }

    func nextChapter() {
        facade.skipToNextChapter()
        facade.refreshWidgets()
    }

    func previousChapter() {
        facade.skipToPreviousChapter()
        facade.refreshWidgets()
    }

    @discardableResult
    func setSleepTimer(minutes: Int) -> Bool {
        guard minutes > 0 else { return false }
        facade.setSleepTimer(seconds: TimeInterval(minutes) * 60)
        facade.refreshWidgets()
        return true
    }

    @discardableResult
    func extendSleepTimer(minutes: Int) -> Bool {
        guard minutes > 0 else { return false }
        facade.extendSleepTimer(bySeconds: TimeInterval(minutes) * 60)
        facade.refreshWidgets()
        return true
    }
}

/// App-process implementation of the control intent's action (the widget
/// extension links a stub of this method instead).
extension PlaybackControlIntent {
    func performPlaybackControlAction(_ action: PlaybackControlAction) {
        PlaybackIntentActionHandler.shared.perform(action)
    }
}

/// Live facade backed by `PlaybackManager`/`DataManager`. The implementations
/// mirror the behaviour previously exposed through the removed SiriKit stack.
nonisolated struct LivePlaybackFacade: PlaybackFacade {
    func isPlaying() -> Bool { PlaybackManager.onMainSync { $0.playing() } }

    func hasCurrentEpisode() -> Bool { PlaybackManager.onMainSync { $0.currentEpisode() != nil } }

    func isSleepTimerActive() -> Bool { PlaybackManager.onMainSync { $0.sleepTimerActive() } }

    func upNextCount() -> Int { PlaybackManager.onMainSync { $0.upNextCount() } }

    func play() { PlaybackManager.onMainSync { $0.play() } }

    func pause() { PlaybackManager.onMainSync { $0.pause() } }

    func playPause() { PlaybackManager.onMainSync { $0.playPause() } }

    func skipBack() { PlaybackManager.onMainSync { $0.skipBack() } }

    func skipForward() { PlaybackManager.onMainSync { $0.skipForward() } }

    func skipToNextChapter() { PlaybackManager.onMainSync { $0.skipToNextChapter(startPlaybackAfterSkip: true) } }

    func skipToPreviousChapter() { PlaybackManager.onMainSync { $0.skipToPreviousChapter(startPlaybackAfterSkip: true) } }

    func removeCurrentEpisodeFromUpNext() {
        PlaybackManager.onMainSync { playbackManager in
            guard let current = playbackManager.currentEpisode() else { return }
            playbackManager.removeIfPlayingOrQueued(episode: current, fireNotification: true, userInitiated: true)
        }
    }

    func loadSuggestedEpisode() async -> Bool {
        guard let suggested = RecommendationHelper().recommendEpisode() else { return false }
        if let episode = DataManager.sharedManager.findEpisode(uuid: suggested.uuid) {
            PlaybackManager.onMainSync { $0.load(episode: episode, autoPlay: true, overrideUpNext: false) }
            return true
        }

        // Await the podcast fetch so Siri/Shortcuts reports the real outcome —
        // an unconditional true here made failures read as success.
        let added = await withCheckedContinuation { continuation in
            ServerPodcastManager.shared.addFromUuid(podcastUuid: suggested.podcastUuid, subscribe: false) { success in
                continuation.resume(returning: success)
            }
        }
        guard added, let episode = DataManager.sharedManager.findEpisode(uuid: suggested.uuid) else { return false }
        await MainActor.run { PlaybackManager.shared.load(episode: episode, autoPlay: true, overrideUpNext: false) }
        return true
    }

    func loadTopEpisode(forFilterUuid uuid: String) -> Bool {
        guard let filter = DataManager.sharedManager.findPlaylist(uuid: uuid) else { return false }
        let request = PlaylistQueryBuilder.filterEpisodesRequest(for: filter, episodeUuidToAdd: filter.episodeUuidToAddToQueries(), limit: 1)
        guard let topEpisode = DataManager.sharedManager.episodes(matching: request).first else { return false }
        PlaybackManager.onMainSync { $0.load(episode: topEpisode, autoPlay: true, overrideUpNext: false) }
        return true
    }

    func playAllEpisodes(forFilterUuid uuid: String) -> Bool {
        guard let filter = DataManager.sharedManager.findPlaylist(uuid: uuid) else { return false }
        PlaybackManager.onMainSync { $0.play(playlist: filter) }
        return true
    }

    func loadTopEpisode(forPodcastUuid uuid: String) -> Bool {
        guard let podcast = DataManager.sharedManager.findPodcast(uuid: uuid) else { return false }
        let sortStr = PodcastEpisodeSortOrder.newestToOldest == podcast.podcastSortOrder ? "DESC" : "ASC"
        let query = "podcast_id = \(podcast.id) AND playingStatus <> \(PlayingStatus.completed.rawValue) AND archived = 0 ORDER BY publishedDate \(sortStr), addedDate \(sortStr) LIMIT 1"
        guard let topEpisode = DataManager.sharedManager.findEpisodesWhere(customWhere: query, arguments: nil).first else { return false }
        PlaybackManager.onMainSync { $0.load(episode: topEpisode, autoPlay: true, overrideUpNext: false) }
        return true
    }

    func setSleepTimer(seconds: TimeInterval) {
        PlaybackManager.onMainSync { $0.setSleepTimerInterval(seconds) }
    }

    func extendSleepTimer(bySeconds seconds: TimeInterval) {
        PlaybackManager.onMainSync { $0.sleepTimeRemaining += seconds }
        NotificationCenter.postOnMainThread(SleepTimerChanged())
    }

    func saveHighlight(source: BookmarkAnalyticsSource) -> Bool {
        PlaybackManager.onMainSync { $0.bookmark(source: source) }
    }

    func refreshWidgets() {
        if let defaults = UserDefaults(suiteName: SharedConstants.GroupUserDefaults.groupContainerId) {
            defaults.set(PlaybackManager.onMainSync { $0.playing() }, forKey: SharedConstants.GroupUserDefaults.isPlaying)
        }
        WidgetCenter.shared.reloadAllTimelines()
        for kind in PlaybackControlKind.all {
            ControlCenter.shared.reloadControls(ofKind: kind)
        }
    }
}
