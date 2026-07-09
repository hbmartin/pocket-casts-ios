import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsServer

@testable import podcasts

/// Inert `PlaybackManaging` test double. Every requirement returns a harmless default
/// (nil/0/false/empty/no-op); the members tests commonly exercise are backed by settable
/// stub vars, and the main transport/queue mutations record their calls for assertions.
///
/// `@MainActor` to match the protocol's isolation (which also supplies the implicit
/// `Sendable` conformance the protocol requires).
@MainActor
final class PlaybackManagingMock: PlaybackManaging {
    // MARK: Stubs

    var currentEpisodeStub: BaseEpisode?
    var playingStub = false
    var currentTimeStub: TimeInterval = 0
    var durationStub: TimeInterval = 0
    var upNextCountStub = 0
    var effectsStub = PlaybackEffects()
    var sleepTimerActiveStub = false

    // MARK: Recorded calls

    /// `userInitiated` value of each `play` call.
    private(set) var playCalls: [Bool] = []
    /// `userInitiated` value of each `pause` call.
    private(set) var pauseCalls: [Bool] = []
    private(set) var loadedEpisodes: [BaseEpisode] = []
    private(set) var addToUpNextEpisodes: [BaseEpisode] = []
    private(set) var seekToTimes: [TimeInterval] = []

    // MARK: Now playing

    var currentPodcast: Podcast?
    var activeError: PlaybackManager.PlaybackError?
    /// Lazy so simply constructing the mock doesn't touch `DataManager.sharedManager`
    /// or `PlaybackManager.shared` (the initializer's default arguments).
    lazy var bookmarkManager = BookmarkManager()

    func currentEpisode() -> BaseEpisode? { currentEpisodeStub }
    func isNowPlayingEpisode(episodeUuid: String?) -> Bool { false }
    func isActivelyPlaying(episodeUuid: String?) -> Bool { false }
    func nowPlayingStarredChanged() { }

    // MARK: Transport

    func load(episode: BaseEpisode, autoPlay: Bool, overrideUpNext: Bool, saveCurrentEpisode: Bool, completion: (() -> Void)?) {
        loadedEpisodes.append(episode)
        completion?()
    }

    func play(completion: (() -> Void)?, userInitiated: Bool) {
        playCalls.append(userInitiated)
        completion?()
    }

    func play(playlist: EpisodeFilter) { }

    func pause(userInitiated: Bool) {
        pauseCalls.append(userInitiated)
    }

    func playPause() { }
    func endPlayback(saveCurrentEpisode: Bool) { }
    func playing() -> Bool { playingStub }
    func buffering() -> Bool { false }
    func isSeeking() -> Bool { false }
    func futureBufferAvailable() -> TimeInterval { 0 }
    func interruptionInProgress() -> Bool { false }
    func currentTime() -> TimeInterval { currentTimeStub }
    func duration() -> TimeInterval { durationStub }
    func requiredStartingPosition() -> TimeInterval { 0 }
    func skipBack() { }
    func skipForward() { }

    func seekTo(time: TimeInterval, startPlaybackAfterSeek: Bool, seekHint: PlaybackManager.SeekHint?) {
        seekToTimes.append(time)
    }

    func seekTo(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool, seekHint: PlaybackManager.SeekHint?) {
        seekToTimes.append(time)
    }

    func retryUrlLoad(for episodeUuid: String) -> Bool { false }
    func internalPlayerForVideoPlayback() -> AVPlayer? { nil }
    func updateIdleTimer() { }

    // MARK: Up Next

    func upNextCount() -> Int { upNextCountStub }
    func upNextQueueCount() -> Int { 0 }
    func upNextTotalDuration(includePlayingEpisode: Bool) -> TimeInterval { 0 }
    func inUpNext(episode: BaseEpisode?) -> Bool { false }
    func episodeInUpNextAt(index: Int) -> BaseEpisode? { nil }

    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool) {
        addToUpNextEpisodes.append(episode)
    }

    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool, userInitiated: Bool) {
        addToUpNextEpisodes.append(episode)
    }

    func bulkAdd(_ episodes: [BaseEpisode], toTop: Bool) { }
    func bulkMoveUpNext(_ playlistEpisodes: [PlaylistEpisode], toTop: Bool) { }
    func bulkRemoveQueued(uuids: [String]) { }
    func moveUpNextEpisode(_ episode: BaseEpisode, to: Int, fireNotification: Bool) { }
    func moveUpNextEpisode(from: Int, to: Int) { }
    func removeIfPlayingOrQueued(episode: BaseEpisode?, fireNotification: Bool, saveCurrentEpisode: Bool, userInitiated: Bool) { }
    func clearUpNextList() { }
    func refreshUpNextList(checkForAutoDownload: Bool) { }
    func recordUpNextUserInteraction() { }
    func upNextBulkOperationDidComplete() { }

    // MARK: Effects

    func effects() -> PlaybackEffects { effectsStub }
    func changeEffects(_ effects: PlaybackEffects) { effectsStub = effects }
    func applyCurrentEffect() { }
    func effectsChangedExternally() { }
    func overrideEffectsToggled(applyLocalSettings: Bool) { }
    func isCurrentEffectGlobal() -> Bool { effectsStub.isGlobal }
    func increasePlaybackSpeed() { }
    func decreasePlaybackSpeed() { }
    func toggleDefinedPlaybackSpeed() { }
    func silenceRemovalAvailable() -> Bool { false }
    func volumeBoostAvailable() -> Bool { false }

    // MARK: Chapters

    var chaptersAreGenerated = false
    func chapterCount(onlyPlayable: Bool) -> Int { 0 }
    func chapterAt(index: Int) -> ChapterInfo? { nil }
    func playableChapterAt(index: Int) -> ChapterInfo? { nil }
    func currentChapters() -> Chapters { Chapters() }
    func chaptersForTime(time: TimeInterval) -> Chapters { Chapters() }
    func skipToPreviousChapter(startPlaybackAfterSkip: Bool) { }
    func skipToNextChapter(startPlaybackAfterSkip: Bool) { }
    func skipToChapter(_ chapter: ChapterInfo, startPlaybackAfterSkip: Bool) { }
    func forceUpdateChapterInfo() { }
    func trackChapterEvent(_ event: AnalyticsEvent, properties: [String: Any]?) { }

    // MARK: Sleep timer

    var sleepTimeRemaining: TimeInterval = 0
    var numberOfEpisodesToSleepAfter = 0
    func sleepTimerActive() -> Bool { sleepTimerActiveStub }
    func setSleepTimerInterval(_ stopIn: TimeInterval) { }
    func cancelSleepTimer(userInitiated: Bool) { }
    func restartSleepTimer() { }

    // MARK: Bookmarks and search

    func bookmark(source: BookmarkAnalyticsSource) { }
    func playBookmark(_ bookmark: Bookmark, source: BookmarkAnalyticsSource, firstTry: Bool) { }
    func playEpisodeSearchResult(_ searchEpisode: EpisodeSearchResult, firstTry: Bool) { }

    // MARK: Player callbacks

    func playbackDidFail(error: PlaybackManager.PlaybackError, fallbackToDefaultPlayer: Bool) { }
    func playerDidFinishPreparing() { }
    func playerDidCalculateDuration() { }
    func playerDidChangeNowPlayingInfo() { }
    func playerDidFinishPlayingEpisode() { }
    func playerDidRequestTermination() { }
}
