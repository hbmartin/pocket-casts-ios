import AVFoundation
import Dependencies
import Foundation
import PocketCastsDataModel
import PocketCastsServer

/// Consumer-facing surface of `PlaybackManager`, registered in the dependency container as
/// `\.playbackManager` so consumers can be tested with a mock instead of the real playback
/// pipeline. Covers the members call sites use today; extend it as adoption grows.
///
/// `@MainActor` because the production conformer (`PlaybackManager`) is main-actor isolated;
/// the isolation makes the protocol implicitly usable as a `Sendable` dependency value.
@MainActor
protocol PlaybackManaging: AnyObject, Sendable {
    // MARK: Now playing

    var currentPodcast: Podcast? { get }
    var activeError: PlaybackManager.PlaybackError? { get set }
    var bookmarkManager: BookmarkManager { get }

    func currentEpisode() -> BaseEpisode?
    func isNowPlayingEpisode(episodeUuid: String?) -> Bool
    func isActivelyPlaying(episodeUuid: String?) -> Bool
    func nowPlayingStarredChanged()

    // MARK: Transport

    func load(episode: BaseEpisode, autoPlay: Bool, overrideUpNext: Bool, saveCurrentEpisode: Bool, completion: (() -> Void)?)
    func play(completion: (() -> Void)?, userInitiated: Bool)
    func play(playlist: EpisodeFilter)
    func pause(userInitiated: Bool)
    func playPause()
    func endPlayback(saveCurrentEpisode: Bool)
    func playing() -> Bool
    func buffering() -> Bool
    func isSeeking() -> Bool
    func futureBufferAvailable() -> TimeInterval
    func interruptionInProgress() -> Bool
    func currentTime() -> TimeInterval
    func duration() -> TimeInterval
    func requiredStartingPosition() -> TimeInterval
    func skipBack()
    func skipForward()
    func seekTo(time: TimeInterval, startPlaybackAfterSeek: Bool, seekHint: PlaybackManager.SeekHint?)
    func seekTo(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool, seekHint: PlaybackManager.SeekHint?)
    func retryUrlLoad(for episodeUuid: String) -> Bool
    func internalPlayerForVideoPlayback() -> AVPlayer?
    func updateIdleTimer()

    // MARK: Up Next

    func upNextCount() -> Int
    func upNextQueueCount() -> Int
    func upNextTotalDuration(includePlayingEpisode: Bool) -> TimeInterval
    func inUpNext(episode: BaseEpisode?) -> Bool
    func episodeInUpNextAt(index: Int) -> BaseEpisode?
    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool)
    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool, userInitiated: Bool)
    func bulkAdd(_ episodes: [BaseEpisode], toTop: Bool)
    func bulkMoveUpNext(_ playlistEpisodes: [PlaylistEpisode], toTop: Bool)
    func bulkRemoveQueued(uuids: [String])
    func moveUpNextEpisode(_ episode: BaseEpisode, to: Int, fireNotification: Bool)
    func moveUpNextEpisode(from: Int, to: Int)
    func removeIfPlayingOrQueued(episode: BaseEpisode?, fireNotification: Bool, saveCurrentEpisode: Bool, userInitiated: Bool)
    func clearUpNextList()
    func refreshUpNextList(checkForAutoDownload: Bool)
    func recordUpNextUserInteraction()
    func upNextBulkOperationDidComplete()

    // MARK: Effects

    func effects() -> PlaybackEffects
    func changeEffects(_ effects: PlaybackEffects)
    func applyCurrentEffect()
    func effectsChangedExternally()
    func overrideEffectsToggled(applyLocalSettings: Bool)
    func isCurrentEffectGlobal() -> Bool
    func increasePlaybackSpeed()
    func decreasePlaybackSpeed()
    func toggleDefinedPlaybackSpeed()
    func silenceRemovalAvailable() -> Bool
    func volumeBoostAvailable() -> Bool

    // MARK: Chapters

    var chaptersAreGenerated: Bool { get }
    func chapterCount(onlyPlayable: Bool) -> Int
    func chapterAt(index: Int) -> ChapterInfo?
    func playableChapterAt(index: Int) -> ChapterInfo?
    func currentChapters() -> Chapters
    func chaptersForTime(time: TimeInterval) -> Chapters
    func skipToPreviousChapter(startPlaybackAfterSkip: Bool)
    func skipToNextChapter(startPlaybackAfterSkip: Bool)
    func skipToChapter(_ chapter: ChapterInfo, startPlaybackAfterSkip: Bool)
    func forceUpdateChapterInfo()
    func trackChapterEvent(_ event: AnalyticsEvent, properties: [String: Any]?)

    // MARK: Sleep timer

    var sleepTimeRemaining: TimeInterval { get set }
    var numberOfEpisodesToSleepAfter: Int { get set }
    func sleepTimerActive() -> Bool
    func setSleepTimerInterval(_ stopIn: TimeInterval)
    func cancelSleepTimer(userInitiated: Bool)
    func restartSleepTimer()

    // MARK: Bookmarks and search

    func bookmark(source: BookmarkAnalyticsSource)
    func playBookmark(_ bookmark: Bookmark, source: BookmarkAnalyticsSource, firstTry: Bool)
    func playEpisodeSearchResult(_ searchEpisode: EpisodeSearchResult, firstTry: Bool)

    // MARK: Player callbacks

    func playbackDidFail(error: PlaybackManager.PlaybackError, fallbackToDefaultPlayer: Bool)
    func playerDidFinishPreparing()
    func playerDidCalculateDuration()
    func playerDidChangeNowPlayingInfo()
    func playerDidFinishPlayingEpisode()
    func playerDidRequestTermination()
}

/// Protocols cannot declare default arguments; these mirror the defaults `PlaybackManager`
/// declares so converted call sites stay source-identical. Each overload has a different
/// arity from its requirement to avoid shadowing the witness.
extension PlaybackManaging {
    func load(episode: BaseEpisode, autoPlay: Bool, overrideUpNext: Bool) {
        load(episode: episode, autoPlay: autoPlay, overrideUpNext: overrideUpNext, saveCurrentEpisode: true, completion: nil)
    }

    func load(episode: BaseEpisode, autoPlay: Bool, overrideUpNext: Bool, completion: (() -> Void)?) {
        load(episode: episode, autoPlay: autoPlay, overrideUpNext: overrideUpNext, saveCurrentEpisode: true, completion: completion)
    }

    func load(episode: BaseEpisode, autoPlay: Bool, overrideUpNext: Bool, saveCurrentEpisode: Bool) {
        load(episode: episode, autoPlay: autoPlay, overrideUpNext: overrideUpNext, saveCurrentEpisode: saveCurrentEpisode, completion: nil)
    }

    func play(userInitiated: Bool = true) {
        play(completion: nil, userInitiated: userInitiated)
    }

    func play(completion: (() -> Void)?) {
        play(completion: completion, userInitiated: true)
    }

    func pause() {
        pause(userInitiated: true)
    }

    func endPlayback() {
        endPlayback(saveCurrentEpisode: true)
    }

    func seekTo(time: TimeInterval, startPlaybackAfterSeek: Bool = false) {
        seekTo(time: time, startPlaybackAfterSeek: startPlaybackAfterSeek, seekHint: nil)
    }

    func seekTo(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool = false) {
        seekTo(time: time, syncChanges: syncChanges, startPlaybackAfterSeek: startPlaybackAfterSeek, seekHint: nil)
    }

    func addToUpNext(episode: BaseEpisode, userInitiated: Bool) {
        addToUpNext(episode: episode, ignoringQueueLimit: false, toTop: false, userInitiated: userInitiated)
    }

    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, userInitiated: Bool) {
        addToUpNext(episode: episode, ignoringQueueLimit: ignoringQueueLimit, toTop: false, userInitiated: userInitiated)
    }

    func bulkAdd(_ episodes: [BaseEpisode]) {
        bulkAdd(episodes, toTop: false)
    }

    func moveUpNextEpisode(_ episode: BaseEpisode, to: Int) {
        moveUpNextEpisode(episode, to: to, fireNotification: true)
    }

    func removeIfPlayingOrQueued(episode: BaseEpisode?, fireNotification: Bool, userInitiated: Bool = false) {
        removeIfPlayingOrQueued(episode: episode, fireNotification: fireNotification, saveCurrentEpisode: true, userInitiated: userInitiated)
    }

    func removeIfPlayingOrQueued(episode: BaseEpisode?, fireNotification: Bool, saveCurrentEpisode: Bool) {
        removeIfPlayingOrQueued(episode: episode, fireNotification: fireNotification, saveCurrentEpisode: saveCurrentEpisode, userInitiated: false)
    }

    func chapterCount() -> Int {
        chapterCount(onlyPlayable: false)
    }

    func skipToPreviousChapter() {
        skipToPreviousChapter(startPlaybackAfterSkip: false)
    }

    func skipToNextChapter() {
        skipToNextChapter(startPlaybackAfterSkip: false)
    }

    func skipToChapter(_ chapter: ChapterInfo) {
        skipToChapter(chapter, startPlaybackAfterSkip: false)
    }

    func trackChapterEvent(_ event: AnalyticsEvent) {
        trackChapterEvent(event, properties: nil)
    }

    func cancelSleepTimer() {
        cancelSleepTimer(userInitiated: false)
    }

    func playBookmark(_ bookmark: Bookmark, source: BookmarkAnalyticsSource) {
        playBookmark(bookmark, source: source, firstTry: true)
    }

    func playEpisodeSearchResult(_ searchEpisode: EpisodeSearchResult) {
        playEpisodeSearchResult(searchEpisode, firstTry: true)
    }

    func playbackDidFail(error: PlaybackManager.PlaybackError) {
        playbackDidFail(error: error, fallbackToDefaultPlayer: false)
    }
}

extension PlaybackManager: PlaybackManaging { }

nonisolated enum PlaybackManagerKey: DependencyKey {
    /// `PlaybackManager.shared` is main-actor isolated, but dependency resolution can start
    /// from a nonisolated context; `onMainSync` is the manager's own bridge for exactly that.
    static var liveValue: any PlaybackManaging {
        PlaybackManager.onMainSync { $0 }
    }
}

nonisolated extension DependencyValues {
    var playbackManager: any PlaybackManaging {
        get { self[PlaybackManagerKey.self] }
        set { self[PlaybackManagerKey.self] = newValue }
    }
}
