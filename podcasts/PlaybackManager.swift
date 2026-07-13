import AVFoundation
import MediaPlayer
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit
import Combine
import Synchronization
import os

/// Owns block-observer tokens so they can be removed when their main-actor owner
/// is released from a nonisolated deinitializer.
nonisolated final class AudioSessionNotificationObservers: Sendable {
    private let notificationCenter: NotificationCenter
    private let observers: UnsafeTransfer<[NSObjectProtocol]>

    init(notificationCenter: NotificationCenter, observers: [NSObjectProtocol]) {
        self.notificationCenter = notificationCenter
        self.observers = UnsafeTransfer(observers)
    }

    deinit {
        for observer in observers.wrappedValue {
            notificationCenter.removeObserver(observer)
        }
    }
}

/// Long-lived audio coordinator, isolated to the main actor (Phase 5,
/// docs/Phase5-PlaybackModernization.md D2). Engine callbacks hop in per-event;
/// real-time audio code stays below this boundary.
@MainActor
final class PlaybackManager {
    static let shared = PlaybackManager()

    /// Lock-guarded mirror of state the audio engines read synchronously from
    /// non-main contexts (Phase 5 D1: real-time-adjacent code can't await).
    /// PlaybackManager updates it on the main actor whenever effects change.
    nonisolated final class EngineStateMirror: Sendable {
        /// Immutable value snapshot consumed by the audio engines. Keeping only Sendable
        /// scalars here prevents the lock from handing a mutable `PlaybackEffects` reference
        /// to background threads after the critical section has ended.
        nonisolated struct PlaybackEffectsSnapshot: Equatable, Sendable {
            let playbackSpeed: Double
            let trimSilenceRawValue: Int32
            let volumeBoost: Bool

            var trimSilence: TrimSilenceAmount {
                TrimSilenceAmount(rawValue: trimSilenceRawValue) ?? .off
            }

            init() {
                playbackSpeed = 1
                trimSilenceRawValue = TrimSilenceAmount.off.rawValue
                volumeBoost = false
            }

            init(_ effects: PlaybackEffects) {
                self.playbackSpeed = effects.playbackSpeed
                self.trimSilenceRawValue = effects.trimSilence.rawValue
                self.volumeBoost = effects.volumeBoost
            }
        }

        /// Live VoiceBoostN meter readouts written from the audio read/tap
        /// threads for the Advanced Audio screen; nil while VBN is inactive.
        nonisolated struct VoiceBoostMeters: Equatable, Sendable {
            var gainDB: Float
            var measuredLUFS: Float
            var limiterReductionDB: Float
        }

        // Effects, tuning, and pendingStartingPosition are Sendable value types, so `Mutex`
        // makes their synchronization compiler-enforced. Live meters are written from the
        // real-time read/tap threads, so they use a non-blocking unfair lock below.
        private let _effects = Mutex(PlaybackEffectsSnapshot())
        var effects: PlaybackEffectsSnapshot {
            _effects.withLock { $0 }
        }

        func publish(effects: PlaybackEffects) {
            let snapshot = PlaybackEffectsSnapshot(effects)
            _effects.withLock { $0 = snapshot }
        }

        private let _tuning = Mutex(AudioTuning.default)
        var tuning: AudioTuning {
            get { _tuning.withLock { $0 } }
            set { _tuning.withLock { $0 = newValue } }
        }

        /// One-shot starting position for EffectsPlayer, captured on the main actor at
        /// play-dispatch time because its locked setup flow can't call back to main
        /// (a main.sync there deadlocks against endPlayback holding playerLock).
        private let _pendingStartingPosition = Mutex<TimeInterval?>(nil)
        var pendingStartingPosition: TimeInterval? {
            get { _pendingStartingPosition.withLock { $0 } }
            set { _pendingStartingPosition.withLock { $0 = newValue } }
        }

        func consumePendingStartingPosition() -> TimeInterval? {
            _pendingStartingPosition.withLock { position in
                defer { position = nil }
                return position
            }
        }

        /// Live VoiceBoostN meters are PUBLISHED from the real-time audio read/tap
        /// threads, which must never block. Writers use a non-blocking trylock and
        /// drop the frame if the (~2 Hz) UI reader holds the lock; the reader blocks.
        private let _voiceBoostMeters = OSAllocatedUnfairLock<VoiceBoostMeters?>(initialState: nil)

        /// Real-time-safe publish from the audio threads. Never blocks: a dropped sample
        /// is imperceptible against the 2 Hz Advanced Audio screen read. The return value
        /// lets one-shot state transitions retry until they are observed.
        @discardableResult
        func publishVoiceBoostMeters(_ meters: VoiceBoostMeters?) -> Bool {
            _voiceBoostMeters.withLockIfAvailable { state in
                state = meters
                return true
            } ?? false
        }

        /// Reliable clear for non-real-time teardown paths.
        func clearVoiceBoostMeters() {
            _voiceBoostMeters.withLock { $0 = nil }
        }

        /// Read by the Advanced Audio screen on the main thread (~2 Hz).
        var voiceBoostMeters: VoiceBoostMeters? {
            _voiceBoostMeters.withLock { $0 }
        }
    }

    /// Static so the engines can reach it without touching the main-actor-isolated `shared`.
    nonisolated static let engineState = EngineStateMirror()

    /// Runs `body` synchronously on the main actor. For legacy nonisolated call paths
    /// (delete/upload flows, playlist query building) where the caller needs the
    /// playback mutation or read to complete before continuing. Callers must never
    /// hold a resource the main actor blocks on.
    nonisolated static func onMainSync<T>(_ body: @MainActor (PlaybackManager) -> T) -> T {
        // assumeIsolated requires a Sendable result; the value never actually crosses
        // threads here (sync execution), so box it through
        if Thread.isMainThread {
            return MainActor.assumeIsolated { PocketCastsUtils.UncheckedSendable(body(shared)) }.value
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { PocketCastsUtils.UncheckedSendable(body(shared)) }
            }.value
        }
    }

    private let updatesPerSave = 30 // save the users progress every 30 seconds

    private var queue: PlaybackQueue
    var uuidOfPlayingList = ""

    private static let notSeeking: TimeInterval = -1
    private var seekingTo: TimeInterval = PlaybackManager.notSeeking

    private let chapterManager = ChapterManager()
    private let positionTracker = PlaybackPositionTracker()

    var sleepTimeRemaining = -1 as TimeInterval

    var numberOfEpisodesToSleepAfter = 0 {
        didSet {
            if numberOfEpisodesToSleepAfter > 0 {
                sleepTimeRemaining = -1
                sleepTimerManager.recordSleepTimerDuration(duration: nil, onEpisodeEnd: true)
                FileLog.shared.addMessage("Sleep Timer: starting with \(numberOfEpisodesToSleepAfter) episodes")
            }
            NotificationCenter.postOnMainThread(SleepTimerChanged())
        }
    }

    private var updateTimer: Timer?
    private var updateCount = 0

    private var currentEffects: PlaybackEffects?
    private var player: PlaybackProtocol?

    private var switchingToDifferentUpNextEpisode = false
    private var interruptInProgress = false

    private var wasPlayingBeforeInterruption = false
    private let aboutToPlay = AtomicBool()

    private let shouldDeactivateSession = AtomicBool()
    private var haveCalledPlayerLoad = false

    private let updateTimerInterval = 1 as TimeInterval

        private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    private var playersToCleanUp = [AnyHashable]()

    private let catchUpHelper = PlaybackCatchUpHelper()

    /// Grows the skip interval on rapid repeated skip taps (see `Settings.seekAccelerationEnabled()`).
    private var seekAcceleration = SeekAccelerationTracker()

    /// Session history of played episodes for the headphone previous-episode action.
    private var episodeHistory = PlayedEpisodeHistory()
    private var isNavigatingBackInHistory = false

    private let analyticsPlaybackHelper = AnalyticsPlaybackHelper.shared

    #if !APPCLIP
    lazy var bookmarkManager: BookmarkManager = {
        BookmarkManager(playbackManager: self)
    }()
    #endif

    private lazy var sleepTimerManager = SleepTimerManager()

    /// The player we should fallback to
    private var fallbackToPlayer: PlaybackProtocol.Type? = nil

    private var lastRetryEpisodeUuid: String?

    private(set) var transcriptsAvailable = false

    /// The time the episode was last switched as tracked by handleCurrentlyPlayingEpisodeUpdated
    private var episodeSwitchTime: Date?
    private var audioSessionNotificationObservers: AudioSessionNotificationObservers?

    /// Typed-message observations, registered once in `init` and removed in deinit.
    private var messageTokens = [NotificationCenter.ObservationToken]()

    init() {
        queue = PlaybackQueue()
        queue.loadPersistedQueue()


        setupRemoteControlSupport()

        audioSessionNotificationObservers = Self.observeAudioSessionNotifications(
            routeChanged: { [weak self] notification in
                self?.handleRouteChanged(notification)
                #if DEBUG
                MediaConcurrencyUITestHarness.audioSessionNotificationHandled(notification.name)
                #endif
            },
            audioInterrupted: { [weak self] notification in
                self?.handleAudioInterruption(notification)
                #if DEBUG
                MediaConcurrencyUITestHarness.audioSessionNotificationHandled(notification.name)
                #endif
            },
            mediaServicesReset: { [weak self] notification in
                self?.handleSystemAudioReset(notification)
                #if DEBUG
                MediaConcurrencyUITestHarness.audioSessionNotificationHandled(notification.name)
                #endif
            }
        )

        Self.engineState.tuning = Settings.audioTuning

        messageTokens.append(NotificationCenter.default.addObserver(for: AudioTuningDidChange.self) { [weak self] _ in
            self?.handleAudioTuningChanged()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: SkipTimesChanged.self) { [weak self] _ in
            self?.handleSkipTimesChanged()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: UserEpisodeUpdated.self) { [weak self] message in
            self?.handleEpisodeDidUpdate(episodeUuid: message.uuid)
            self?.updateNowPlayingInfo()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: EpisodeDownloaded.self) { [weak self] message in
            self?.handleEpisodeDidDownload(episodeUuid: message.uuid)
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: ExtraMediaSessionActionsChanged.self) { [weak self] _ in
            self?.updateExtraActions()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: RemoteCommandSettingsChanged.self) { [weak self] _ in
            self?.refreshRemoteCommands()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: EpisodeEmbeddedArtworkLoaded.self) { [weak self] _ in
            self?.updateAllNowPlayingData()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: PodcastChaptersDidUpdate.self) { [weak self] _ in
            self?.updateAllNowPlayingData()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: CurrentlyPlayingEpisodeUpdated.self) { [weak self] _ in
            self?.handleCurrentlyPlayingEpisodeUpdated()
        })

        // deferred because some of these call our singleton instance back, which would
        // crash if run inside init (PlaybackManager.shared re-entry); the task only
        // runs after init returns
        Task { @MainActor in
            self.updateAllNowPlayingData()
            self.updateChapterInfo()
            self.queue.updateUpNextInfo()
        }
    }

    deinit {
        // Read isolated stored properties into locals before any observer removal
        // (Swift 6.2 isolated-deinit rule).
        let tokens = messageTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    nonisolated static func observeAudioSessionNotifications(
        notificationCenter: NotificationCenter = .default,
        routeChanged: @escaping @MainActor @Sendable (Notification) -> Void,
        audioInterrupted: @escaping @MainActor @Sendable (Notification) -> Void,
        mediaServicesReset: @escaping @MainActor @Sendable (Notification) -> Void
    ) -> AudioSessionNotificationObservers {
        let observers = [
            notificationCenter.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { notification in
                // OperationQueue.main guarantees synchronous main-thread delivery. The
                // wrapper expresses that this Foundation payload is not concurrently shared.
                let notification = UnsafeTransfer(notification)
                MainActor.assumeIsolated {
                    routeChanged(notification.wrappedValue)
                }
            },
            notificationCenter.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
                let notification = UnsafeTransfer(notification)
                MainActor.assumeIsolated {
                    audioInterrupted(notification.wrappedValue)
                }
            },
            notificationCenter.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { notification in
                let notification = UnsafeTransfer(notification)
                MainActor.assumeIsolated {
                    mediaServicesReset(notification.wrappedValue)
                }
            }
        ]
        return AudioSessionNotificationObservers(notificationCenter: notificationCenter, observers: observers)
    }

    // MARK: - API

    func isNowPlayingEpisode(episodeUuid: String?) -> Bool {
        if let episodeUuid, let playingEpisode = currentEpisode() {
            return playingEpisode.uuid == episodeUuid
        }

        return false
    }

    func isActivelyPlaying(episodeUuid: String?) -> Bool {
        isNowPlayingEpisode(episodeUuid: episodeUuid) && playing()
    }

    func currentEpisode() -> BaseEpisode? {
        queue.currentEpisode()
    }

    var currentPodcast: Podcast? {
        if let episode = currentEpisode() as? Episode {
            return episode.parentPodcast()
        }

        return nil
    }

    func playing() -> Bool {
        if aboutToPlay.value { return true }

        guard let player else { return false }

        return player.playing()
    }

    func buffering() -> Bool {
        guard let player else { return false }

        return player.buffering()
    }

    func futureBufferAvailable() -> TimeInterval {
        player?.futureBufferAvailable() ?? 0
    }

    func recordUpNextUserInteraction() {
        queue.recordUpNextUserInteraction()
    }

    func load(episode: BaseEpisode, autoPlay: Bool, overrideUpNext: Bool, saveCurrentEpisode: Bool = true, completion: (() -> Void)? = nil) {
        FileLog.shared.addMessage("Loading \(episode.displayableTitle()) with UUID \(episode.uuid) autoPlay \(autoPlay) overrideUpNext: \(overrideUpNext)")

        let episodeIsChanging = episode.uuid != currentEpisode()?.uuid

        // if the user has built an Up Next list, preserve that but make this the currently playing episode
        if !overrideUpNext && !switchingToDifferentUpNextEpisode && queue.upNextCount() > 0 {
            if let currEpisode = currentEpisode(), currEpisode.uuid != episode.uuid {
                switchTo(episodeToPlay: episode, moveExistingToUpNext: true, autoPlay: true, completion: completion)

                return
            }
        }

        seekAcceleration.reset()

        // Session history for the headphone previous-episode action. Recording after the
        // switchTo early-return above avoids double-recording (switchTo re-enters load).
        if episodeIsChanging, !isNavigatingBackInHistory, let outgoingUuid = currentEpisode()?.uuid {
            episodeHistory.record(uuid: outgoingUuid)
        }

        if let uuid = currentEpisode()?.uuid, uuid != episode.uuid {
            chapterManager.clearChapterInfo()
        }

        if saveCurrentEpisode && currentEpisode() != nil && !switchingToDifferentUpNextEpisode {
            recordPlaybackPosition(sendToServerImmediately: false, fireNotifications: false)
        }

        // pressing play/pause when using the Effects Player will cause the code to go through here again, but we only need to mess with the Up Next if we're not playing the same episode anymore
        if episodeIsChanging {
            if overrideUpNext || queue.upNextCount() == 0 {
                queue.overrideAllEpisodesWith(episode: episode)
            } else {
                queue.pushNewCurrentlyPlaying(episode: episode)
            }
        } else {
            // even if the episode isn't changing, we might have a stale copy of it, so update ours
            queue.nowPlayingEpisodeChanged()

            if overrideUpNext {
                queue.clearUpNextList()
            }
        }
        uuidOfPlayingList = ""

        cleanupCurrentPlayer(permanent: false)
        setupPlayer()

        // Played and unplayed episodes should always start from 0
        if episode.played() || episode.unplayed() {
            positionTracker.overridePosition(0, episodeUuid: episode.uuid)
            DataManager.sharedManager.saveEpisode(playedUpTo: 0, episode: episode, updateSyncFlag: false)
            queue.refreshList(checkForAutoDownload: false)
        }
        DataManager.sharedManager.updateEpisodePlaybackInteractionDate(episode: episode)
        DataManager.sharedManager.saveEpisode(playbackError: nil, episode: episode)
        activeError = nil

        if autoPlay {
            NotificationCenter.postOnMainThread(PlaybackStarting())
            play(completion: completion)
        } else if episodeIsChanging {
            NotificationCenter.postOnMainThread(UpNextQueueChanged())
        }
    }

    func play(completion: (() -> Void)? = nil, userInitiated: Bool = true) {
        guard let currEpisode = currentEpisode() else { return }

        FileLog.shared.addMessage("PlaybackManager Play \(currentEpisode()?.title ?? "unknown episode") userInitiated: \(userInitiated)")

        if userInitiated {
            analyticsPlaybackHelper.play()
        }

        aboutToPlay.value = true

        if playerSwitchRequired() {
            load(episode: currEpisode, autoPlay: false, overrideUpNext: false)
        }
        if !haveCalledPlayerLoad {
            player?.loadEpisode(currEpisode)
            haveCalledPlayerLoad = true
        }

        activateAudioSession(completion: { activated in
            if !activated {
                self.aboutToPlay.value = false
                return
            }

            if self.player is EffectsPlayer {
                // EffectsPlayer consumes this in startReadAndPlayThreads; see EngineStateMirror
                Self.engineState.pendingStartingPosition = self.requiredStartingPosition()
            }
            self.player?.play {
                completion?()
            }
            self.startUpdateTimer()
            self.updateCommandCenterSkipTimes(addTarget: false)
            self.updateExtraActions()

            NotificationCenter.postOnMainThread(PlaybackStarted())

            if currEpisode.videoPodcast() {
                self.setAudioSessionVideoProperties()
            }

            self.updateIdleTimer()

            self.sleepTimerManager.restartSleepTimerIfNeeded()
        })
    }

    func pause(userInitiated: Bool = true) {
        guard let episode = currentEpisode() else { return }

        // Only trigger the event if we are already playing
        if playing(), userInitiated == true {
            analyticsPlaybackHelper.pause()
        }

        // one kind of interruption would be to launch siri and ask it to pause, handle this here
        wasPlayingBeforeInterruption = false

        FileLog.shared.addMessage("PlaybackManager pausing playback \(currentEpisode()?.title ?? "unknown episode")")

        recordPlaybackPosition(sendToServerImmediately: playing(), fireNotifications: true)

        if let player {
            player.pause()
        }
        updateNowPlayingInfo()

        seekAcceleration.reset()
        catchUpHelper.playbackDidPause(of: episode, playedUpTo: positionTracker.playedUpTo(for: episode))
        NotificationCenter.postOnMainThread(PlaybackPaused())
        cancelUpdateTimer()
        deactiveAudioSession()

        updateIdleTimer()
    }

    func playPause() {
        if playing() {
            pause()
        } else {
            play()
        }
    }

    func skipBack() {
        var skipBackAmount = TimeInterval(Settings.skipBackTime)
        if Settings.seekAccelerationEnabled() {
            skipBackAmount = seekAcceleration.amount(for: .back, baseAmount: skipBackAmount)
        }
        skipBack(amount: skipBackAmount)
    }

    private func skipBack(amount: TimeInterval) {
        analyticsPlaybackHelper.skipBack()

        let currPos = currentTime()
        let backTime = max(currPos - amount, 0)
        seekTo(time: backTime, seekHint: .back)
    }

    func skipForward() {
        var skipForwardAmount = TimeInterval(Settings.skipForwardTime)
        if Settings.seekAccelerationEnabled() {
            skipForwardAmount = seekAcceleration.amount(for: .forward, baseAmount: skipForwardAmount)
        }
        skipForward(amount: skipForwardAmount)
    }

    private func skipForward(amount: TimeInterval) {
        analyticsPlaybackHelper.skipForward()

        let forwardTime = min(currentTime() + amount, duration())
        seekTo(time: forwardTime, seekHint: .forward)

        StatsManager.shared.addSkippedTime(amount)
    }

    func skipToPreviousChapter(startPlaybackAfterSkip: Bool = false) {
        guard let previousChapter = chapterManager.previousVisibleChapter() else { return }

        if abs(currentChapters().index - previousChapter.index) > 1 {
            trackChapterSkipped()
        }

        seekTo(time: ceil(previousChapter.startTime.seconds), startPlaybackAfterSeek: startPlaybackAfterSkip)
    }

    func skipToNextChapter(startPlaybackAfterSkip: Bool = false) {
        guard let nextChapter = chapterManager.nextVisiblePlayableChapter() else {
            // If there are no more chapters to play, we skip to the end of the last chapter
            // We do that because for some episodes the last chapter might not necessarily
            // be the end of the episode. So we don't make this assumption here and respect
            // whatever the producer set.
            skipToEndOfLastChapter()
            return
        }

        if abs(currentChapters().index - nextChapter.index) > 1 {
            trackChapterSkipped()
        }

        seekTo(time: ceil(nextChapter.startTime.seconds), startPlaybackAfterSeek: startPlaybackAfterSkip)
    }

    func skipToChapter(_ chapter: ChapterInfo, startPlaybackAfterSkip: Bool = false) {
        seekTo(time: ceil(chapter.startTime.seconds), startPlaybackAfterSeek: startPlaybackAfterSkip)
    }

    /// Jumps to the next episode in Up Next (headphone/lock-screen next-episode action).
    /// A no-op when the queue is empty.
    func skipToNextEpisode() {
        guard queue.upNextCount() > 0 else {
            FileLog.shared.addMessage("skipToNextEpisode ignored: Up Next is empty")
            return
        }

        analyticsPlaybackHelper.track(.playbackNextEpisode)
        playNextEpisode(autoPlay: true)
    }

    /// Music-player-style previous action (headphone/lock-screen previous-episode action):
    /// more than `restartThreshold` seconds into the episode → restart it from 0; otherwise pop
    /// the session history and return to the previously played episode (fallback: restart).
    func skipToPreviousEpisodeOrRestart(restartThreshold: TimeInterval = 15) {
        analyticsPlaybackHelper.track(.playbackPreviousEpisode)

        if currentTime() > restartThreshold {
            seekTo(time: 0)
            return
        }

        var previousEpisode: BaseEpisode?
        while let uuid = episodeHistory.popPrevious() {
            if let episode = DataManager.sharedManager.findBaseEpisode(uuid: uuid) {
                previousEpisode = episode
                break
            }
        }

        guard let previousEpisode else {
            FileLog.shared.addMessage("skipToPreviousEpisodeOrRestart: no usable history, restarting current episode")
            seekTo(time: 0)
            return
        }

        FileLog.shared.addMessage("skipToPreviousEpisodeOrRestart: returning to \(previousEpisode.displayableTitle())")

        // Deliberately not load(episode:): with an empty Up Next, load would hit
        // overrideAllEpisodesWith and drop the current episode instead of re-queueing it.
        // Inserting at the queue front and switching pushes the current episode to the
        // front of Up Next (via pushNewCurrentlyPlaying), so "next" returns to it.
        isNavigatingBackInHistory = true
        queue.insert(episode: previousEpisode, position: 0)
        switchToPlaying(upNextIndex: 0)
        isNavigatingBackInHistory = false
    }

    func skipToEndOfLastChapter() {
        if let lastChapter = chapterManager.lastChapter {
            seekTo(time: ceil(lastChapter.startTime.seconds) + lastChapter.duration)
        }
    }

    func chapterCount(onlyPlayable: Bool = false) -> Int {
        onlyPlayable ? chapterManager.playableChapterCount() : chapterManager.visibleChapterCount()
    }

    var chaptersAreGenerated: Bool {
        return chapterManager.chaptersOrigin == .generated
    }

    func index(for chapter: Chapters) -> Int? {
        chapterManager.index(for: chapter)
    }

    func chapterAt(index: Int) -> ChapterInfo? {
        chapterManager.chapterAt(index: index)
    }

    func playableChapterAt(index: Int) -> ChapterInfo? {
        chapterManager.playableChapterAt(index: index)
    }

    func currentChapters() -> Chapters {
        chapterManager.currentChapters
    }

    func chaptersForTime(time: TimeInterval) -> Chapters {
        chapterManager.chaptersForTime(time)
    }

    func playableChaptersUpdated() {
        // Check if current chapter still needs to be played
        if currentChapters().visibleChapter?.isPlayable() == false {
            skipToNextChapter()
        }
    }

    /// The user re-enabled a chapter in the chapters UI: exempt it from smart-skip rules for the
    /// rest of the session so a chapter reload doesn't immediately re-deselect it.
    func registerChapterSessionReEnable(chapterIndex: Int, episodeUuid: String) {
        chapterManager.registerSessionReEnable(chapterIndex: chapterIndex, episodeUuid: episodeUuid)
    }

    /// The user deselected a chapter again: drop any session smart-skip exemption for it.
    func unregisterChapterSessionReEnable(chapterIndex: Int, episodeUuid: String) {
        chapterManager.unregisterSessionReEnable(chapterIndex: chapterIndex, episodeUuid: episodeUuid)
    }

    private func checkForChapterChange() {
        guard let episodeUuid = currentEpisode()?.uuid else { return }

        if chapterManager.haveTriedToParseChaptersFor(episodeUuid: episodeUuid), chapterManager.updateCurrentChapter(time: currentTime()) {
            if currentChapters().visibleChapter?.isPlayable() == false {
                skipToNextChapter()
                trackChapterSkipped()
            } else {
                fireChapterChangeNotification()
                updateAllNowPlayingData()
            }
        }
    }

    func isSeeking() -> Bool {
        seekingTo != PlaybackManager.notSeeking
    }

    func seekTo(time: TimeInterval, startPlaybackAfterSeek: Bool = false, seekHint: SeekHint? = nil) {
        seekTo(time: time, syncChanges: SyncManager.isUserLoggedIn(), startPlaybackAfterSeek: startPlaybackAfterSeek, seekHint: seekHint)
    }

    func seekToFromSync(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool) {
        analyticsPlaybackHelper.currentSource = .sync
        seekTo(time: time, syncChanges: syncChanges, startPlaybackAfterSeek: startPlaybackAfterSeek)
    }

    enum SeekHint {
        case back
        case forward
    }

    func seekTo(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool = false, seekHint: SeekHint? = nil) {
        // any non-skip seek (scrubber, chapter jump, bookmark, sync) breaks a skip-acceleration streak
        if seekHint == nil {
            seekAcceleration.reset()
        }

        guard let playingEpisode = currentEpisode() else { return } // nothing to actually seek

        if seekHint == .back, !isValidSeek(time: time) {
            FileLog.shared.addMessage("aborting seek because it's moving forward from \(previousSeekTime ?? 0) to \(time)")
            return
        }

        // if we're seeking an episode, and it's not in progress, it should be
        if !playingEpisode.inProgress() {
            DataManager.sharedManager.saveEpisode(playingStatus: .inProgress, episode: playingEpisode, updateSyncFlag: SyncManager.isUserLoggedIn())
        }

        let currentTime = positionTracker.playedUpTo(for: playingEpisode)
        seekingTo = time
        FileLog.shared.addMessage("seek to \(time) startPlaybackAfterSeek \(startPlaybackAfterSeek)")

        let isReadyToPlay = player?.isReadyToPlay() == true
        if let player, isReadyToPlay {
            player.seekTo(time, completion: { [weak self] () in
                guard let strongSelf = self else { return }

                strongSelf.seekingTo = PlaybackManager.notSeeking

                strongSelf.recordPlaybackPosition(sendToServerImmediately: false, fireNotifications: true)
                strongSelf.checkForChapterChange()
                strongSelf.fireProgressNotification()
                strongSelf.updateNowPlayingInfo()

                if startPlaybackAfterSeek, !strongSelf.playing() {
                    strongSelf.play()
                }
            })
        } else {
            // the player isn't currently initialised, so just set this time directly on the episode, as long as it's not past the duration
            if time >= 0, time <= playingEpisode.duration, time != positionTracker.playedUpTo(for: playingEpisode) {
                DataManager.sharedManager.saveEpisode(playedUpTo: time, episode: playingEpisode, updateSyncFlag: syncChanges)

                seekingTo = PlaybackManager.notSeeking
                NotificationCenter.postOnMainThread(PlaybackPositionSaved(uuid: playingEpisode.uuid))
                checkForChapterChange()
                fireProgressNotification()
                updateNowPlayingInfo()
            } else {
                seekingTo = PlaybackManager.notSeeking
            }

            if startPlaybackAfterSeek, !playing() {
                play(userInitiated: false)
            }
        }

        analyticsPlaybackHelper.seek(from: currentTime, to: time, duration: playingEpisode.duration)
    }

    private var previousSeekTime: TimeInterval?
    private let debouncer = Debounce(delay: 1.second)

    // When using EffectsPlayer we have an issue in which rapidly tapping
    // skip back results (sometimes) in skipping forward
    // Here we handle that to avoid this issue
    // See https://github.com/Automattic/pocket-casts-ios/issues/1950
    private func isValidSeek(time: TimeInterval) -> Bool {
        if let previousSeekTime, time > previousSeekTime {
            return false
        }

        previousSeekTime = time

        debouncer.call { [weak self] in
            self?.previousSeekTime = nil
        }

        return true
    }

    func currentTime() -> TimeInterval {
        guard let episode = currentEpisode() else { return -1 }

        if seekingTo >= 0, seekingTo <= duration(), !playing() { return seekingTo }

        let playerTime = !aboutToPlay.value ? player?.currentTime() ?? 0 : 0

        if playerTime <= 0 {
            let startFromTime = startFromTimeForCurrentEpisode()
            let storedUpTo = positionTracker.playedUpTo(for: episode)
            return storedUpTo < 1 ? startFromTime : storedUpTo
        }

        return playerTime
    }

    func duration() -> TimeInterval {
        guard let currentEpisode = currentEpisode() else { return 0 }

        if let player, !aboutToPlay.value, !buffering() {
            let episodeDuration = currentEpisode.duration
            let playerDuration = player.duration()
            return (playerDuration > 0) ? playerDuration : episodeDuration
        }

        return currentEpisode.duration
    }

    // MARK: - Up Next
    func inUpNext(episode: BaseEpisode?) -> Bool {
        guard let episode else { return false }

        return Self.episodeIsInUpNext(uuid: episode.uuid)
    }

    /// Pure DB query; static + nonisolated so background callers (episode cleanup,
    /// formatting helpers) can check Up Next membership without hopping to main.
    nonisolated static func episodeIsInUpNext(uuid: String) -> Bool {
        #if APPCLIP
        return false
        #else
        return DataManager.sharedManager.upNextPlayListContains(episodeUuid: uuid)
        #endif
    }

    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool) {
        #if !APPCLIP
        addToUpNext(episode: episode, ignoringQueueLimit: ignoringQueueLimit, toTop: toTop, userInitiated: false)
        #endif
    }

    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool = false, toTop: Bool = false, userInitiated: Bool) {
        if userInitiated {
            AnalyticsEpisodeHelper.shared.episodeAddedToUpNext(episode: episode, toTop: toTop)
        }

        // If we don't have a current episode, reload the persisted queue to updated our cache just in case
        // We're getting reports from users about Up Next being cleared where this line is indicated by the logs
        if currentEpisode() == nil {
            FileLog.shared.addMessage("PlaybackManager: Missing current episode, reloading queue")
            queue.loadPersistedQueue()
        }

        guard let playingEpisode = currentEpisode() else {
            // if there's nothing playing, just play this
            load(episode: episode, autoPlay: false, overrideUpNext: true)

            return
        }

        if playingEpisode.uuid == episode.uuid { return }

        // if the episode is somewhere in our future queue, ignore this add call
        if queue.contains(episode: episode), !toTop {
            return
        }

        // check the queue isn't already full
        if !ignoringQueueLimit, queue.upNextCount() >= ServerSettings.autoAddToUpNextLimit() {
            return
        }

        if let episode = episode as? Episode, episode.archived {
            EpisodeManager.unarchiveEpisode(episode: episode, fireNotification: true, userInitiated: false)
        }

        if episode.played() {
            EpisodeManager.markAsUnplayed(episode: episode, fireNotification: true, userInitiated: false)
        }

        // otherwise we don't have this item, so add it to the bottom of our future list
        queue.add(episode: episode, fireNotification: true, partOfBulkAdd: false, toTop: toTop)
    }

    func removeIfPlayingOrQueued(episode: BaseEpisode?, fireNotification: Bool, saveCurrentEpisode: Bool = true, userInitiated: Bool = false) {
        if userInitiated, let episode {
            AnalyticsEpisodeHelper.shared.episodeRemovedFromUpNext(episode: episode)
        }
        if isNowPlayingEpisode(episodeUuid: episode?.uuid) {
            autoplayIfNeeded()
            if queue.upNextCount() > 0 {
                playNextEpisode(autoPlay: playing())
            } else {
                endPlayback(saveCurrentEpisode: saveCurrentEpisode)
            }

            return
        }

        if let episode {
            queue.remove(episode: episode, fireNotification: fireNotification)
        }
    }

    func bulkRemoveQueued(uuids: [String]) {
        queue.bulkDelete(uuids: uuids)
    }

    func switchToPlaying(upNextIndex: Int) {
        if upNextIndex >= queue.upNextCount() { return }

        if let episodeToPlay = queue.episodeAt(index: upNextIndex) {
            switchTo(episodeToPlay: episodeToPlay, moveExistingToUpNext: true, autoPlay: true)
        }
    }

    private func playNextEpisode(autoPlay: Bool) {
        let queueCount = queue.upNextCount()
        if queueCount == 0 { return }

        var index = 0
        if queueCount > 1, Settings.upNextShuffleEnabled() {
            index = Int.random(in: 0..<queueCount)
            FileLog.shared.addMessage("Play Next Episode with Shuffle enabled: playing episode \(index) out of \(queueCount)")
        }

        guard let nextEpisode = queue.episodeAt(index: index) else { return }

        FileLog.shared.addMessage("Play Next Episode \(nextEpisode.displayableTitle())")

        if queueCount > 1, index > 0 {
            queue.move(episode: nextEpisode, to: 0)
        }

        seekAcceleration.reset()

        // this path bypasses load(episode:), so record the outgoing episode here
        if let outgoingUuid = currentEpisode()?.uuid {
            episodeHistory.record(uuid: outgoingUuid)
        }

        queue.removeTopEpisode(fireNotification: false)
        chapterManager.clearChapterInfo()
        cleanupCurrentPlayer(permanent: !autoPlay)

        // Played and unplayed episodes should always start from 0
        if nextEpisode.played() || nextEpisode.unplayed() {
            positionTracker.overridePosition(0, episodeUuid: nextEpisode.uuid)
        }
        DataManager.sharedManager.saveEpisode(playbackError: nil, episode: nextEpisode)
        activeError = nil

        if autoPlay {
            play(userInitiated: false)
        } else {
            NotificationCenter.postOnMainThread(UpNextQueueChanged())
        }

        numberOfEpisodesToSleepAfter -= 1
        NotificationCenter.postOnMainThread(PlaybackTrackChanged())
    }

    private func switchTo(episodeToPlay: BaseEpisode, moveExistingToUpNext: Bool, autoPlay: Bool, completion: (() -> Void)? = nil) {
        cancelUpdateTimer()

        if let previousEpisode = currentEpisode(), !moveExistingToUpNext {
            queue.remove(episode: previousEpisode, fireNotification: false)
        }

        switchingToDifferentUpNextEpisode = true
        load(episode: episodeToPlay, autoPlay: autoPlay, overrideUpNext: false, completion: completion)
        switchingToDifferentUpNextEpisode = false

        NotificationCenter.postOnMainThread(PlaybackTrackChanged())
        NotificationCenter.postOnMainThread(UpNextQueueChanged())
    }

    func play(playlist: EpisodeFilter) {
        let playlistEpisodes: [Episode]
        let request = PlaylistQueryBuilder.episodesRequest(for: playlist, episodeUuidToAdd: playlist.episodeUuidToAddToQueries(), limit: ServerSettings.autoAddToUpNextLimit(), shouldShowArchived: playlist.showArchivedEpisodes)
        playlistEpisodes = DataManager.sharedManager.episodes(matching: request)
        if playlist.manual {
            let archivedEpisodes = playlistEpisodes.filter(\.archived)
            EpisodeManager.bulkUnarchive(episodes: archivedEpisodes, trackEvent: false)
        }
        guard let startingEpisode = playlistEpisodes.first else { return }

        populateFrom(episodes: playlistEpisodes, startingAtEpisode: startingEpisode)
        uuidOfPlayingList = playlist.uuid
    }

    func internalPlayerForVideoPlayback() -> AVPlayer? {
        if let episode = currentEpisode(), player == nil {
            load(episode: episode, autoPlay: false, overrideUpNext: false)
            player?.loadEpisode(episode)
            haveCalledPlayerLoad = true
        }

        if let player {
            // in order for things like Picture in Picture to work properly, an audio session needs to be activated. If the UI is asking for the internal AVPlayer, then make sure we do this
            activateAudioSession(completion: nil)
            return player.internalPlayerForVideoPlayback()
        }
        setAudioSessionVideoProperties()

        return nil
    }

    func endPlayback(saveCurrentEpisode: Bool = true) {
        cancelUpdateTimer()
        cancelSleepTimer()
        chapterManager.clearChapterInfo()
        seekAcceleration.reset()
        episodeHistory.removeAll()

        if saveCurrentEpisode {
            recordPlaybackPosition(sendToServerImmediately: false, fireNotifications: true)
        }

        queue.removeAllEpisodes()
        cleanupCurrentPlayer(permanent: true)
            NowPlayingHelper.clearNowPlayingInfo()

        NotificationCenter.postOnMainThread(PlaybackEnded())
    }

    private var deactivateTimedActionHelper = TimedActionHelper()
    private func deactiveAudioSession(waitBeforeDeactivating: Bool = true) {
        if !waitBeforeDeactivating {
            performDeactivate(audioSession: AVAudioSession.sharedInstance())
            return
        }

        shouldDeactivateSession.value = true
        // iOS gets cranky if you try to de-activate a session that's playing audio, and calling pause doesn't immediately cause audio to stop playing, so as a workaround wait a bit then do it
        deactivateTimedActionHelper.startTimer(for: 3.seconds) { [weak self] in
            guard let self else { return }

            let audioSession = AVAudioSession.sharedInstance()
            if !self.shouldDeactivateSession.value { return }
            self.shouldDeactivateSession.value = false
            self.performDeactivate(audioSession: audioSession)
        }
    }

    private func performDeactivate(audioSession: AVAudioSession) {
        do {
            try audioSession.setActive(false)
            FileLog.shared.addMessage("deactiveAudioSession succeeded")
        } catch {
            FileLog.shared.addMessage("deactiveAudioSession failed")
        }
    }

    func playingEpisodeChangedExternally() {
        FileLog.shared.addMessage("Playing episode changed externally")
        chapterManager.clearChapterInfo()
        cleanupCurrentPlayer(permanent: true)

        // if the episode is downloaded, parse it for chapters so the UI is up to date. If it's not, don't, because this will use data
        if let episode = currentEpisode(), episode.downloaded(pathFinder: DownloadManager.shared) {
            updateChapterInfo()
        }
    }

    func connectedToRemotePlayerWithEpisode(_ episode: Episode) {
        NotificationCenter.postOnMainThread(PlaybackStarted())
    }

    func playingOverAirplay() -> Bool {
        Self.isPlayingOverAirplay()
    }

    /// Pure AVAudioSession read; static + nonisolated so the engines' KVO callbacks can call it.
    nonisolated static func isPlayingOverAirplay() -> Bool {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute

        if currentRoute.outputs.isEmpty { return false }

        let currentOutput = currentRoute.outputs[0]
        if currentOutput.portType.rawValue == AVAudioSession.Port.airPlay.rawValue {
            return true
        }

        return false
    }

    func effects() -> PlaybackEffects {
        if let currentEffects {
            return currentEffects
        }
        let effects = loadEffects()
        currentEffects = effects
        Self.engineState.publish(effects: effects)
        return effects
    }

    func applyCurrentEffect() {
        guard let currentEffects else { return }
        changeEffects(currentEffects)
    }

    func changeEffects(_ effects: PlaybackEffects) {
        guard let episode = currentEpisode() else { return }

        // round it to the nearest 0.1, so we end up with 1.5 not 1.53667346262
        effects.playbackSpeed = round(effects.playbackSpeed * 10.0) / 10.0

        // persist changes
        if effects.isGlobal {
            if FeatureFlag.newSettingsStorage.enabled {
                SettingsStore.appSettings.trimSilence = TrimSilence(amount: effects.trimSilence)
                SettingsStore.appSettings.volumeBoost = effects.volumeBoost
                SettingsStore.appSettings.playbackSpeed = effects.playbackSpeed
            } else {
                UserDefaults.standard.set(effects.trimSilence.rawValue, forKey: Constants.UserDefaults.globalRemoveSilence)
                UserDefaults.standard.set(effects.volumeBoost, forKey: Constants.UserDefaults.globalVolumeBoost)
                UserDefaults.standard.set(effects.playbackSpeed, forKey: Constants.UserDefaults.globalPlaybackSpeed)
            }
        } else if let episode = episode as? Episode, var podcast = episode.parentPodcast() {
            if FeatureFlag.newSettingsStorage.enabled {
                podcast.settings.trimSilence = TrimSilence(amount: effects.trimSilence)
                podcast.settings.playbackSpeed = effects.playbackSpeed
                podcast.settings.boostVolume = effects.volumeBoost
                podcast.syncStatus = SyncStatus.notSynced.rawValue
            }
            podcast.trimSilenceAmount = Int32(effects.trimSilence.rawValue)
            podcast.playbackSpeed = effects.playbackSpeed
            podcast.boostVolume = effects.volumeBoost

            DataManager.sharedManager.save(podcast: podcast)
            NotificationCenter.postOnMainThread(PodcastUpdated(uuid: podcast.uuid))
        }

        currentEffects = effects
        Self.engineState.publish(effects: effects)
        handlePlaybackEffectsChanged(effects: effects)
    }

    func decreasePlaybackSpeed() {
        let playbackEffects = effects()
        if playbackEffects.playbackSpeed < 0.6 { return }

        playbackEffects.playbackSpeed = playbackEffects.playbackSpeed - 0.1
        changeEffects(playbackEffects)
    }

    func toggleDefinedPlaybackSpeed() {
        let playbackEffects = effects()
        playbackEffects.toggleDefinedSpeedInterval()

        changeEffects(playbackEffects)
    }

    func increasePlaybackSpeed() {
        let playbackEffects = effects()
        if playbackEffects.playbackSpeed > 4.9 { return }

        playbackEffects.playbackSpeed = playbackEffects.playbackSpeed + 0.1
        changeEffects(playbackEffects)
    }

    func effectsChangedExternally() {
        let newEffects = loadEffects()
        currentEffects = newEffects
        Self.engineState.publish(effects: newEffects)
        handlePlaybackEffectsChanged(effects: newEffects)
    }

    private func handleAudioTuningChanged() {
        let oldTuning = Self.engineState.tuning
        let newTuning = Settings.audioTuning
        guard oldTuning != newTuning else { return }

        Self.engineState.tuning = newTuning

        if oldTuning.timeStretch.effectsPlayerAlgorithm != newTuning.timeStretch.effectsPlayerAlgorithm,
           player is EffectsPlayer, let episode = currentEpisode() {
            // the EffectsPlayer time-stretch unit is wired into the engine graph at
            // build time, so an algorithm change needs a player rebuild
            load(episode: episode, autoPlay: playing(), overrideUpNext: false)
            return
        }

        player?.effectsDidChange()
    }

    func overrideEffectsToggled(applyLocalSettings: Bool) {
        guard let episode = currentEpisode() as? Episode,
              let podcast = episode.parentPodcast() else {
            return
        }
        overrideEffectsToggled(applyLocalSettings: applyLocalSettings, for: podcast)
    }

    func overrideEffectsToggled(applyLocalSettings: Bool, for podcast: Podcast) {
        var podcast = podcast
        podcast.isEffectsOverridden = applyLocalSettings

        DataManager.sharedManager.save(podcast: podcast)
        NotificationCenter.postOnMainThread(PodcastUpdated(uuid: podcast.uuid))

        effectsChangedExternally()
    }

    func isCurrentEffectGlobal() -> Bool {
        return effects().isGlobal
    }

    private func handlePlaybackEffectsChanged(effects: PlaybackEffects) {
        guard let episode = currentEpisode() else { return }

        if playerSwitchRequired() {
            load(episode: episode, autoPlay: playing(), overrideUpNext: false)
        }

        if let player {
            player.effectsDidChange()
        }
        updateAllNowPlayingData()

        NotificationCenter.postOnMainThread(PlaybackEffectsChanged())
    }

    func silenceRemovalAvailable() -> Bool {
        #if APPCLIP
        if let episode = currentEpisode() {
            return !episode.videoPodcast()
        }
        #elseif !os(tvOS)
            if let episode = currentEpisode() {
                return !episode.videoPodcast()
            }
        #endif

        return false
    }

    func volumeBoostAvailable() -> Bool {
            return true
    }

    // MARK: - Player Callbacks

    @objc func requiredStartingPosition() -> TimeInterval {
        guard let episode = currentEpisode() else { return 0 }

        if seekingTo >= 0, seekingTo <= duration() {
            let timeToReturn = seekingTo
            seekingTo = PlaybackManager.notSeeking

            return timeToReturn
        }

        if Int(episode.playingStatus) == PlayingStatus.inProgress.rawValue {
            let storedUpTo = positionTracker.playedUpTo(for: episode)
            if storedUpTo > 0 {
                return catchUpHelper.adjustStartTimeIfNeeded(for: episode, playedUpTo: storedUpTo)
            }
        } else {
            DataManager.sharedManager.saveEpisode(playingStatus: PlayingStatus.inProgress, episode: episode, updateSyncFlag: SyncManager.isUserLoggedIn())

            let startTime = startFromTimeForCurrentEpisode()
            if startTime > 0 {
                let seekAheadTime = Double(startTime)
                StatsManager.shared.addAutoSkipTime(seekAheadTime)

                return seekAheadTime
            }
        }

        return 0
    }

    @objc func playerDidFinishPreparing() {
        // to speed things up, we report the player as playing before it actually has, this callback is so it can tell us when it has
        aboutToPlay.value = false

        // make sure we load the saved speed for this track
        if let player {
            player.setPlaybackRate(effects().playbackSpeed)
        }

        updateAllNowPlayingData()
    }

    enum PlaybackError: Error {
        case internetConnection(logMessage: String?)
        case episodeNotAvailable(errorCode: Int, logMessage: String?)
        case fileCorrupted(logMessage: String?)
        case playbackError(logMessage: String?, isLocalFile: Bool)

        var userMessage: String {
            switch self {
            case .internetConnection:
                return L10n.playerErrorInternetConnection
            case .episodeNotAvailable:
                return L10n.downloadErrorContactAuthorVersion2
            case .fileCorrupted:
                return L10n.playerErrorCorruptedFile
            case .playbackError(_, let isLocalFile):
                return isLocalFile ? L10n.playerErrorCorruptedFile : L10n.playerErrorInternetConnection
            }
        }

        var shortUserMessage: String {
            switch self {
            case .internetConnection:
                return L10n.playerErrorShortNoConnection
            case .episodeNotAvailable:
                return L10n.playerErrorEpisodeNotAvailable
            case .fileCorrupted:
                return L10n.playerErrorCorruptedFile
            case .playbackError:
                return L10n.playerErrorShortPlaybackError
            }
        }

        func shortUserAttributedMessage(mainColor: UIColor, interactiveColor: UIColor) -> NSAttributedString {
            let baseText = self.shortUserMessage
            let learnMore = String(L10n.learnMore).sentenceCased
            let attributedString = NSMutableAttributedString(string: baseText, attributes: [.foregroundColor: mainColor, .font: UIFont.systemFont(ofSize: 14, weight: .medium)])
            if self.userAction != nil {
                attributedString.append(NSAttributedString(string: " ", attributes: [.foregroundColor: mainColor, .font: UIFont.systemFont(ofSize: 14, weight: .medium)]))
                attributedString.append(NSAttributedString(string: learnMore, attributes: [.foregroundColor: interactiveColor, .font: UIFont.systemFont(ofSize: 14, weight: .medium)]))
            }
            return attributedString
        }

        var userAction: URL? {
            switch self {
            case .episodeNotAvailable(let errorCode, _):
                switch errorCode {
                case NSURLErrorUserAuthenticationRequired:
                    return URL(string: ServerConstants.Urls.supportEpisodeAccessIssues)
                case NSURLErrorFileDoesNotExist:
                    return URL(string: ServerConstants.Urls.supportEpisodeNotFound)
                case NSURLErrorBadServerResponse:
                    return URL(string: ServerConstants.Urls.supportEpisodeServerProblem)
                default:
                    return URL(string: ServerConstants.Urls.supportPlaybackDownloadErrors)
                }
            default:
                return nil
            }
        }

        var logMessage: String? {
            switch self {
            case .internetConnection(let logMessage):
                return logMessage
            case .episodeNotAvailable(_, let logMessage):
                return logMessage
            case .fileCorrupted(let logMessage):
                return logMessage
            case .playbackError(let logMessage, _):
                return logMessage
            }
        }

        static let knownURLErrors: [Int] = [NSURLErrorResourceUnavailable, NSURLErrorBadServerResponse, NSURLErrorUserAuthenticationRequired, NSURLErrorFileDoesNotExist, NSURLErrorZeroByteResource]
    }

    var activeError: PlaybackError?

    func playbackDidFail(error: PlaybackError, fallbackToDefaultPlayer: Bool = false) {
        FileLog.shared.addMessage("[PlaybackManager] Playback did fail with error: \(error.logMessage ?? "No error detail provided")")

        AnalyticsPlaybackHelper.shared.playbackFailed(episodeUUID: currentEpisode()?.uuid ?? "unknown", error: error.logMessage ?? "Unknown", player: player)

        if fallbackToDefaultPlayer, let episode = currentEpisode() {
            FileLog.shared.addMessage("[PlaybackManager] Playback failed, attempting to fallback to: DefaultPlayer")

            fallbackToPlayer = DefaultPlayer.self

            load(episode: episode, autoPlay: true, overrideUpNext: false) { [weak self] in
                self?.fallbackToPlayer = nil
            }
            return
        }

        guard let episode = currentEpisode() else {
            FileLog.shared.addMessage("[PlaybackManager] Failed to fetch current episode. Queue will be cleared.")
            endPlayback()

            return
        }

        // sometimes the end of a file can be corrupt, we handle this here with a few basic checks:
        // - Did we get more than a minute into the show?
        // - Is where we are up to close to the duration?
        // - Is the duration actually reasonable?
        // if either of these is false, flag it as an error, otherwise we got close enough to the end
        let finishedUpTo = positionTracker.playedUpTo(for: episode)
        if finishedUpTo < 1.minutes || episode.duration <= 0 || ((finishedUpTo + 3.minutes) < episode.duration) {
            let previousSource = AnalyticsPlaybackHelper.shared.currentSource
            AnalyticsPlaybackHelper.shared.currentSource = .playbackFailed
            pause(userInitiated: false)
            AnalyticsPlaybackHelper.shared.currentSource = previousSource
            NotificationCenter.postOnMainThread(PlaybackPaused())
            activeError = error
            let message = error.userMessage
            DataManager.sharedManager.saveEpisode(playbackError: message, episode: episode)

            if !episode.downloaded(pathFinder: DownloadManager.shared) {
                cleanupCurrentPlayer(permanent: false)
            }

            NotificationCenter.postOnMainThread(PlaybackFailed())

            return
        }

        FileLog.shared.addMessage("[PlaybackManager] Something odd about the end of this episode but we got close enough, marking as finished")
        playerDidFinishPlayingEpisode()
    }

    func playerDidCalculateDuration() {
        guard let episode = currentEpisode(), let playerDuration = player?.duration(), !episode.downloading() else { return }

        let currentDuration = episode.duration

        if currentDuration < 10 || abs(currentDuration - playerDuration) > 10 {
            DataManager.sharedManager.saveEpisode(duration: playerDuration, episode: episode, updateSyncFlag: SyncManager.isUserLoggedIn())
            NotificationCenter.postOnMainThread(EpisodeDurationChanged(uuid: episode.uuid))
        }

        fireProgressNotification()
        updateNowPlayingInfo()
    }

    func playerDidChangeNowPlayingInfo() {
        updateNowPlayingInfo()
        NotificationCenter.postOnMainThread(CurrentlyPlayingEpisodeUpdated())
    }

    func playerDidFinishPlayingEpisode() {
        if numberOfEpisodesToSleepAfter == 1 {
            pauseAndRecordSleepTimerFinished()
            cancelSleepTimer()
            return
        }
        // once playback is over iOS can be aggressive about killing off our app, so start a short-lived background task to let it know we're doing stuff
        startBackgroundTask()
        defer {
            endBackgroundTask()
        }

        cancelUpdateTimer()
        seekingTo = PlaybackManager.notSeeking
        chapterManager.clearChapterInfo()

        // handle the episode that just finished, marking it as played, etc
        if var episode = currentEpisode() {
            autoplayIfNeeded()

            FileLog.shared.addMessage("Finished playing \(episode.displayableTitle())")
            Analytics.track(.playerEpisodeCompleted, properties: [
                "podcast_uuid": episode.parentIdentifier(),
                "episode_uuid": episode.uuid
            ])
            episode.playingStatus = PlayingStatus.completed.rawValue
            episode.playedUpTo = episode.duration

            if SyncManager.isUserLoggedIn() {
                let currentUtcTime = TimeFormatter.currentUTCTimeInMillis()
                episode.playingStatusModified = currentUtcTime
                episode.playedUpToModified = currentUtcTime
            }

            if var typedEpisode = episode as? Episode {
                typedEpisode.lastPlaybackInteractionDate = Date()
                typedEpisode.lastPlaybackInteractionSyncStatus = SyncStatus.notSynced.rawValue
                episode = typedEpisode
            }
            DataManager.sharedManager.save(episode: episode)

            if SyncManager.isUserLoggedIn() {
                FileLog.shared.addMessage("Sending playback completed to API server")
                ApiServerHandler.shared.saveCompleted(episode: episode)
            }

            // if marking an episode as played means the it should be archived, then do that
            if EpisodeManager.shouldArchiveOnCompletion(episode: episode) {
                if let episode = episode as? Episode {
                    EpisodeManager.archiveEpisode(episode: episode, fireNotification: true, removeFromPlayer: false, userInitiated: false)
                } else if let episode = episode as? UserEpisode {
                    // No App Clip episodes should be user episodes
                    #if !APPCLIP
                    if Settings.userEpisodeRemoveFileAfterPlaying() {
                        UserEpisodeManager.deleteFromDevice(userEpisode: episode, removeFromPlaybackQueue: false)
                    }
                    #endif
                }
            } else {
                EpisodeManager.cleanupUnusedBuffers(episode: episode)
            }
        }

        // check to see if there's another episode we should be moving onto
        if queue.upNextCount() == 0 {
            if let episode = currentEpisode() {
                queue.remove(episode: episode, fireNotification: false)
            }
            NotificationCenter.postOnMainThread(PlaybackEnded())
            cleanupCurrentPlayer(permanent: true)

                NowPlayingHelper.clearNowPlayingInfo()

            cancelSleepTimer()
        } else {
            playNextEpisode(autoPlay: !(numberOfEpisodesToSleepAfter == 1))
        }
    }

    func playerDidRequestTermination() {
        guard let currEpisode = currentEpisode() else { return }

        let upTo = currentTime()
        DataManager.sharedManager.saveEpisode(playedUpTo: upTo, episode: currEpisode, updateSyncFlag: SyncManager.isUserLoggedIn())

        cleanupCurrentPlayer(permanent: true)

        NotificationCenter.postOnMainThread(PlaybackPositionSaved(uuid: currEpisode.uuid))
        updateNowPlayingInfo()
    }

    func bulkAdd(_ episodes: [BaseEpisode], toTop: Bool = false) {
        var episodesToAdd = episodes
        if let currentEpisodeIndex = episodes.firstIndex(where: { $0.uuid == PlaybackManager.shared.currentEpisode()?.uuid }) {
            episodesToAdd.remove(at: currentEpisodeIndex)
        }

        // it's technically possible to try and add just the now playing episode, in which case there's nothing more to do
        if episodesToAdd.isEmpty {
            queue.bulkOperationDidComplete()

            return
        }

        queue.bulkAdd(episodesToAdd, toTop: toTop)

        for episode in episodesToAdd {
            if let episode = episode as? Episode, episode.archived {
                EpisodeManager.unarchiveEpisode(episode: episode, fireNotification: false)
            }

            if episode.played() {
                EpisodeManager.markAsUnplayed(episode: episode, fireNotification: false, userInitiated: false)
            }
        }
        queue.bulkOperationDidComplete()

        AnalyticsEpisodeHelper.shared.bulkAddToUpNext(count: episodesToAdd.count, toTop: toTop)
    }

    // MARK: - Helper Methods

    private func populateFrom(episodes: [BaseEpisode]?, startingAtEpisode: BaseEpisode) {
        if episodes == nil, queue.upNextCount() > 0 {
            // the user has chosen to play a single episode, and they have an up next list, so add this episode into up next and push the rest down
            switchTo(episodeToPlay: startingAtEpisode, moveExistingToUpNext: true, autoPlay: true)
        } else {
            // there's a new list of episodes to play, so clear what's currently playing and play that
            load(episode: startingAtEpisode, autoPlay: true, overrideUpNext: true)
            NotificationCenter.postOnMainThread(PlaybackTrackChanged())

            let filteredEpisodes = episodes!.filter { $0.uuid != startingAtEpisode.uuid }
            if filteredEpisodes.isEmpty {
                return
            }
            queue.bulkAdd(filteredEpisodes)
        }
    }

    private func playerSwitchRequired() -> Bool {
        let possiblePlayers = supportedPlayers()
        if let player, let firstSupportedPlayer = possiblePlayers.first {
            return type(of: player) != firstSupportedPlayer
        }

        return true
    }

    private func setupPlayer() {
        guard let currEpisode = currentEpisode() else { return }

        // check for rogue settings
        if currEpisode.videoPodcast() {
            let currEffects = effects()
            currEffects.trimSilence = .off
        }

        let playersSupported = supportedPlayers()
        #if os(tvOS)
            FileLog.shared.addMessage("Using DefaultPlayer")
            player = DefaultPlayer()
        #elseif APPCLIP
            if playersSupported.first == EffectsPlayer.self {
                FileLog.shared.addMessage("Using EffectsPlayer")
                player = EffectsPlayer()
            } else {
                FileLog.shared.addMessage("Using DefaultPlayer")
                player = DefaultPlayer()
            }
        #else
            if playersSupported.first == EffectsPlayer.self {
                FileLog.shared.addMessage("Using EffectsPlayer")
                player = EffectsPlayer()
            } else {
                FileLog.shared.addMessage("Using DefaultPlayer")
                player = DefaultPlayer()
            }
        #endif
    }

    private func supportedPlayers() -> [PlaybackProtocol.Type] {
        var possiblePlayers = [PlaybackProtocol.Type]()

        guard let currEpisode = currentEpisode() else { return possiblePlayers }

        #if !APPCLIP && !os(tvOS)
            if let fallbackToPlayer {
                return [fallbackToPlayer]
            }
        #endif

        #if !os(tvOS)
        if !playingOverAirplay(), !currEpisode.videoPodcast(), (currEpisode.downloaded(pathFinder: DownloadManager.shared) && effects().trimSilence != .off) || currEpisode.bufferedForStreaming() {
            possiblePlayers.append(EffectsPlayer.self)
        }
        #endif

        possiblePlayers.append(DefaultPlayer.self)

        return possiblePlayers
    }

    private func cleanupCurrentPlayer(permanent: Bool) {
        haveCalledPlayerLoad = false
        seekingTo = PlaybackManager.notSeeking
        FileLog.shared.addMessage("cleanupCurrentPlayer permanent? \(permanent)")
        if let player {
            player.endPlayback(permanent: permanent)
        }

        if permanent { aboutToPlay.value = false }
        currentEffects = nil

        // DefaultPlayer and EffectsPlayer both have issues if you discard them immediately after stopping them. DefaultPlayer will crash while trying to render more audio and EffectsPlayer has internal issues as well.
        // This fix isn't ideal, but removing it before fixing these two issues will cause more crashing
        if let player = player as? AnyHashable {
            playersToCleanUp.append(player)
            let boxedPlayer = PocketCastsUtils.UncheckedSendable(player)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }

                let index = self.playersToCleanUp.firstIndex(where: { listPlayer -> Bool in
                    listPlayer == boxedPlayer.value
                })
                if let index {
                    self.playersToCleanUp.remove(at: index)
                }

                if !self.playing() {
                    self.deactiveAudioSession(waitBeforeDeactivating: false)
                }
            }
        }

        player = nil
    }

    func activateAudioSession(completion: ((Bool) -> Void)?) {
        shouldDeactivateSession.value = false

        // Perform audio session activation on a background queue to avoid blocking the main thread
        let boxedCompletion = PocketCastsUtils.UncheckedSendable(completion)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                boxedCompletion.value?(false)
                return
            }
            self.activateSession(completion: boxedCompletion.value)
        }
    }

    nonisolated private func activateSession(completion: ((Bool) -> Void)?) {
        do {
            try Self.setAudioSessionProperties()
            try AVAudioSession.sharedInstance().setActive(true)
            FileLog.shared.addMessage("activating audio session succeeded")
            completion?(true)
        } catch {
            FileLog.shared.addMessage("activating audio session failed \(error.localizedDescription)")
            completion?(false)
        }
    }

    nonisolated private static func setAudioSessionProperties() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
    }

    private func setAudioSessionVideoProperties() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setMode(AVAudioSession.Mode.moviePlayback)
        } catch {}
    }

    private func loadEffects() -> PlaybackEffects {
        guard let episode = queue.currentEpisode() as? Episode, let podcast = episode.parentPodcast() else {
            return PlaybackEffects.globalEffects()
        }

        return PlaybackEffects.effectsFor(podcast: podcast)
    }

    func queuePersistLocalCopyAsReplace() {
        queue.persistLocalCopyAsReplace()
    }

    func queueRefreshList(checkForAutoDownload: Bool) {
        queue.refreshList(checkForAutoDownload: checkForAutoDownload)
    }

    func allEpisodesInQueue(includeNowPlaying: Bool) -> [BaseEpisode] {
        queue.allEpisodes(includeNowPlaying: includeNowPlaying)
    }

    func allEpisodeUuidsInQueue() -> [BaseEpisode] {
        queue.allEpisodeUuids()
    }

    func upNextQueueChanged() {
        NotificationCenter.postOnMainThread(UpNextQueueChanged())
    }

    func upNextQueueCount() -> Int {
        queue.upNextCount()
    }

    func removeLastEpisodeFromUpNext() {
        guard let lastEpisode = queue.allEpisodes().last else { return }

        queue.remove(uuid: lastEpisode.uuid, fireNotification: true)
    }

    // MARK: - Playback Position

    private func recordPlaybackPosition(sendToServerImmediately: Bool, fireNotifications: Bool) {
        guard let currEpisode = currentEpisode() else { return }

        let upTo = currentTime()
        if upTo <= 0 { return }

        let isUserLoggedIn = SyncManager.isUserLoggedIn()
        DataManager.sharedManager.saveEpisode(playedUpTo: upTo, episode: currEpisode, updateSyncFlag: isUserLoggedIn)
        DataManager.sharedManager.updateEpisodePlaybackInteractionDate(episode: currEpisode)
        FileLog.shared.addMessage("saving played up to \(upTo) for episode \(currEpisode.displayableTitle())")
        if sendToServerImmediately, isUserLoggedIn {
            ApiServerHandler.saveUpTo(time: upTo, duration: duration(), episode: currEpisode)
        }

        if fireNotifications {
            NotificationCenter.postOnMainThread(PlaybackPositionSaved(uuid: currEpisode.uuid))
            updateNowPlayingInfo()
        }

        StatsManager.shared.persistTimes()
    }

    private func startUpdateTimer() {
        // schedule the timer on a thread that has a run loop, the main thread being a good option
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateTimer?.invalidate()
            updateTimer = nil
            self.updateTimer = Timer.scheduledTimer(timeInterval: self.updateTimerInterval, target: self, selector: #selector(self.progressTimerFired), userInfo: nil, repeats: true)
        }
    }

    private func cancelUpdateTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateTimer?.invalidate()
            updateTimer = nil
        }
    }

    @objc private func progressTimerFired() {
        guard let player, let episode = currentEpisode() else { return }

        StatsManager.shared.addTotalListeningTime(updateTimerInterval)
        if player.playbackRate() > 1 {
            StatsManager.shared.addTimeSavedVariableSpeed((updateTimerInterval * player.playbackRate()) - updateTimerInterval)
        }

        // check for outro skipping
        let skipLast = skipLastTimeForCurrentEpisode()
        if skipLast > 0 {
            let episodeDuration = duration()
            let timeRemaining = episodeDuration - currentTime()
            if episodeDuration > 0, episodeDuration > skipLast, timeRemaining < skipLast {
                if numberOfEpisodesToSleepAfter == 1 {
                    pause()
                    cancelSleepTimer()
                } else {
                    FileLog.shared.addMessage("Skipping last \(timeRemaining) seconds of episode because podcast has skip last of \(skipLast) set.")
                    StatsManager.shared.addAutoSkipTime(timeRemaining)
                    EpisodeManager.markAsPlayed(episode: episode, fireNotification: true)
                }
                return
            }
        }

        checkForChapterChange()
        fireProgressNotification()

        if updateCount > updatesPerSave {
            recordPlaybackPosition(sendToServerImmediately: playing(), fireNotifications: true)
            updateCount = 0
        } else {
            let upTo = currentTime()
            if upTo > 0 {
                positionTracker.tick(upTo: upTo, episodeUuid: episode.uuid)
            }
            updateCount += 1
        }

        // here (as above) we're assuming that in general the timer fires around once a second. Might have to investigate this though as it might not always be the case
        if sleepTimeRemaining >= 0 {
            if sleepTimeRemaining == sleepTimerManager.sleepTimerFadeDuration {
                sleepTimerManager.performFadeOut(player: player)
            }

            sleepTimeRemaining = sleepTimeRemaining - updateTimerInterval

            if sleepTimeRemaining < 0 {
                pauseAndRecordSleepTimerFinished()
            }
        }

        if player.buffering() == false {
            updateChapterInfo()
        }
    }

    private func pauseAndRecordSleepTimerFinished() {
        sleepTimerManager.recordSleepTimerFinished()
        pause()
    }

    private func fireProgressNotification() {
        if isSeeking() { return } // don't fire these while the app is seeking

        if Thread.isMainThread {
            if isBackgrounded() { return }

            NotificationCenter.postOnMainThread(PlaybackProgressed())
        } else {
            DispatchQueue.main.sync {
                if isBackgrounded() { return }

                NotificationCenter.postOnMainThread(PlaybackProgressed())
            }
        }
    }

    private func fireChapterChangeNotification() {
        NotificationCenter.postOnMainThread(PodcastChapterChanged())
    }

    private func isBackgrounded() -> Bool {
        // Playback code asks this from its own queues; bridge the UIKit read
        if Thread.isMainThread {
            return MainActor.assumeIsolated { UIApplication.shared.applicationState == .background }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { UIApplication.shared.applicationState == .background }
            }
        }
    }

    // MARK: - Now Playing Info

    /// The playback rate to report to the system Now Playing info center.
    ///
    /// When paused, the players still return their configured speed (e.g. `1.0`) from
    /// `playbackRate()`, so reporting that to the system makes Control Center / the Lock
    /// Screen extrapolate elapsed time and keep the timeline ticking even though playback
    /// is stopped. Reporting `nil` here is interpreted as a rate of `0`, which holds the
    /// timeline in place while paused. See PCIOS-274.
    private var nowPlayingPlaybackRate: Double? {
        playing() ? player?.playbackRate() : nil
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode() else {
                NowPlayingHelper.clearNowPlayingInfo()

            return
        }
            NowPlayingHelper.updateNowPlayingInfo(for: episode, currentChapters: currentChapters(), duration: duration(), upTo: currentTime(), playbackRate: nowPlayingPlaybackRate)
    }

    func forceUpdateChapterInfo() {
        queue.nowPlayingEpisodeChanged()

        guard let episode = currentEpisode(), episode.mayContainChapters() else { return }

        chapterManager.parseChapters(episode: episode, duration: duration())
    }

    private func updateChapterInfo() {
        guard let episode = currentEpisode(), episode.mayContainChapters(), !chapterManager.haveTriedToParseChaptersFor(episodeUuid: episode.uuid) else { return }

        chapterManager.parseChapters(episode: episode, duration: duration())
    }

    private func updateAllNowPlayingData() {
        guard let episode = currentEpisode() else {
                NowPlayingHelper.clearNowPlayingInfo()
            return
        }

            NowPlayingHelper.setAllNowPlayingInfo(for: episode, currentChapters: currentChapters(), duration: duration(), upTo: currentTime(), playbackRate: nowPlayingPlaybackRate)
    }

    // MARK: - Sleep Timer

    func cancelSleepTimer(userInitiated: Bool = false) {
        sleepTimerManager.cancelSleepTimer(userInitiated: userInitiated)
        sleepTimeRemaining = -1
        numberOfEpisodesToSleepAfter = 0
        NotificationCenter.postOnMainThread(SleepTimerChanged())
    }

    func sleepTimerActive() -> Bool {
        sleepTimeRemaining >= 0 || numberOfEpisodesToSleepAfter > 0
    }

    func setSleepTimerInterval(_ stopIn: TimeInterval) {
        FileLog.shared.addMessage("Sleep Timer: starting with \(stopIn)")
        sleepTimerManager.recordSleepTimerDuration(duration: stopIn, onEpisodeEnd: nil)
        sleepTimeRemaining = stopIn
        NotificationCenter.postOnMainThread(SleepTimerChanged())
        Analytics.track(.playerSleepTimerEnabled, properties: ["time": Int(stopIn)])
    }

    func restartSleepTimer() {
        guard sleepTimerActive() else {
            return
        }

        #if !APPCLIP && !os(tvOS)
        Toast.show(L10n.deviceShakeSleepTimer)
        #endif
        sleepTimerManager.restartSleepTimer()
    }

    // MARK: - Remote Control support

    private var lastSeekTime = Date()
    private func setupRemoteControlSupport() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            strongSelf.analyticsPlaybackHelper.currentSource = strongSelf.commandCenterSource

            FileLog.shared.addMessage("Remote control: togglePlayPauseCommand")
            strongSelf.playPause()

            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            strongSelf.analyticsPlaybackHelper.currentSource = strongSelf.commandCenterSource

            FileLog.shared.addMessage("Remote control: pauseCommand")
            strongSelf.pause()

            return .success
        }

        commandCenter.playCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            strongSelf.analyticsPlaybackHelper.currentSource = strongSelf.commandCenterSource

            if Settings.legacyBluetoothModeEnabled() {
                FileLog.shared.addMessage("Remote control: playCommand, treating as play (Legacy BT Mode is on)")
                if !strongSelf.playing() { strongSelf.play() }
            } else if let lastPlayTime = UserDefaults.standard.object(forKey: Constants.UserDefaults.lastPlayEvent) as? Date, fabs(lastPlayTime.timeIntervalSinceNow) < 10.seconds {
                // iOS will sometimes issue two remotePlay commands, so if it's been less than 10 seconds since the last one, just play don't try to playPause
                FileLog.shared.addMessage("Remote control: playCommand, treating as play")
                if !strongSelf.playing() { strongSelf.play() }
            } else {
                if strongSelf.playingOverAirplay() {
                    // during handoff iOS will call us to play even if we already are, so honour that here
                    FileLog.shared.addMessage("Remote control: playCommand, treating as play because playing over AirPlay")
                    if !strongSelf.playing() { strongSelf.play() }
                } else {
                    if AVAudioSession.sharedInstance().isOtherAudioPlaying {
                        FileLog.shared.addMessage("Remote control: playCommand, ignored because other audio is playing")
                        return .commandFailed
                    }
                    // we hook play up to play/pause because that's how some headphones/car stereos do it instead of sending distinct play/pause events
                    FileLog.shared.addMessage("Remote control: playCommand, treating as playPause")
                    strongSelf.playPause()
                }
            }
            UserDefaults.standard.set(Date(), forKey: Constants.UserDefaults.lastPlayEvent)

            return .success
        }

        commandCenter.stopCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            FileLog.shared.addMessage("Remote control: stopCommand")
            strongSelf.pause()

            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            FileLog.shared.addMessage("Remote control: previousTrackCommand")

            // you can ask Siri to say 'rewind 2 minutes' and it will set the skip interval to a custom number, here we honour that number
            if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
                strongSelf.skipBack(amount: skipEvent.interval)
            } else {
                strongSelf.analyticsPlaybackHelper.currentSource = strongSelf.commandCenterSource
                strongSelf.handleRemoteAction(Settings.headphonesPreviousAction)
            }

            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            FileLog.shared.addMessage("Remote control: nextTrackCommand")

            // you can ask Siri to say 'skip forward 2 minutes' and it will set the skip interval to a custom number, here we honour that number
            if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
                strongSelf.skipForward(amount: skipEvent.interval)
            } else {
                strongSelf.analyticsPlaybackHelper.currentSource = strongSelf.commandCenterSource
                strongSelf.handleRemoteAction(Settings.headphonesNextAction)
            }

            return .success
        }

        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let strongSelf = self, let _ = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

            if let rateEvent = event as? MPChangePlaybackRateCommandEvent {
                FileLog.shared.addMessage("Remote control: changePlaybackRateCommand")
                let currentEffects = strongSelf.effects()
                currentEffects.playbackSpeed = Double(rateEvent.playbackRate)
                strongSelf.changeEffects(currentEffects)

                return .success
            }

            FileLog.shared.addMessage("Remote control: changePlaybackRateCommand failed")
            return .commandFailed
        }

        updateCommandCenterSkipTimes(addTarget: true)

        updateExtraActions()

        refreshRemoteCommands()
    }

    private func refreshRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        if !Settings.isLockScreenScrubbingDisabled { // Only perform the seek if lock screen scrubbing is enabled
            commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in

                guard let self, let _ = currentEpisode() else { return .noActionableNowPlayingItem }

                analyticsPlaybackHelper.currentSource = commandCenterSource

                if let seekEvent = event as? MPChangePlaybackPositionCommandEvent {
                    if Settings.legacyBluetoothModeEnabled(), seekEvent.positionTime < 1 {
                        FileLog.shared.addMessage("Remote control: ignoring changePlaybackPositionCommand, it's to 0 and legacy bluetooth mode is on")
                    } else {
                        FileLog.shared.addMessage("Remote control: changePlaybackPositionCommand to \(seekEvent.positionTime)")

                        // Check if we're still in the limiting window after an episode change
                        if let switchTime = episodeSwitchTime,
                           Date.now.timeIntervalSince(switchTime) < 2.0 {
                            FileLog.shared.addMessage("Remote control: ignoring changePlaybackPositionCommand due to recent episode switch")
                            return .commandFailed
                        }

                        seekTo(time: seekEvent.positionTime)
                    }

                    return .success
                }

                FileLog.shared.addMessage("Remote control: changePlaybackPositionCommand failed")

                return .commandFailed
            }
        }
    }

    private func updateExtraActions() {
        let actionsEnabled = Settings.extraMediaSessionActionsEnabled()

        let markPlayedCommand = MPRemoteCommandCenter.shared().dislikeCommand
        let starCommand = MPRemoteCommandCenter.shared().likeCommand

        if actionsEnabled {
            #if !APPCLIP && !os(tvOS)
                markPlayedCommand.setTitle(title: L10n.markPlayedShort)
            #endif
            markPlayedCommand.removeTarget(nil)
            markPlayedCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
                guard let strongSelf = self, let episode = strongSelf.currentEpisode() else { return .noActionableNowPlayingItem }

                AnalyticsEpisodeHelper.shared.currentSource = strongSelf.commandCenterSource
                EpisodeManager.markAsPlayed(episode: episode, fireNotification: true)
                return .success
            }
            markPlayedCommand.isEnabled = true

            #if !APPCLIP && !os(tvOS)
                starCommand.setTitle(title: L10n.starEpisodeShort)
            #endif
            starCommand.removeTarget(nil)
            starCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
                guard let strongSelf = self, let episode = strongSelf.currentEpisode() as? Episode else { return .noActionableNowPlayingItem }
                EpisodeManager.setStarred(!episode.keepEpisode, episode: episode, updateSyncStatus: SyncManager.isUserLoggedIn())
                return .success
            }
            if let episode = self.currentEpisode() {
                starCommand.isActive = episode.keepEpisode
            } else {
                starCommand.isActive = false
            }
            if self.currentEpisode() is UserEpisode {
                starCommand.isEnabled = false
            }
            else {
                starCommand.isEnabled = true
            }
        } else {
            markPlayedCommand.removeTarget(nil)
            markPlayedCommand.isEnabled = false

            starCommand.removeTarget(nil)
            starCommand.isEnabled = false
        }
    }

    // MARK: - Skip Time Changes

    private func handleSkipTimesChanged() {
        updateCommandCenterSkipTimes(addTarget: false)
    }

    private func updateCommandCenterSkipTimes(addTarget: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()

        let skipBackAmount = TimeInterval(Settings.skipBackTime)
        if addTarget {
            setInterval(commandCenter.skipBackwardCommand, interval: skipBackAmount) { event -> MPRemoteCommandHandlerStatus in
                let skipChapters = Settings.headphonesPreviousAction == .previousChapter

                // if the user has remote chapter skipping on, try to honour that setting if there's no interval that comes through, or the interval matches the default one
                if skipChapters, let previousChapter = self.chapterManager.previousVisibleChapter() {
                    let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? TimeInterval(Settings.skipBackTime)
                    if Int(interval) == Settings.skipBackTime {
                        FileLog.shared.addMessage("Skipping to previous chapter because Remote Skip Chapters is turned on")
                        self.seekTo(time: ceil(previousChapter.startTime.seconds))

                        return .success
                    }
                }

                // same hijack for the previous-episode headphone action; a mismatched
                // interval is a Siri custom skip and passes through to a plain skip
                if Settings.headphonesPreviousAction == .previousEpisode {
                    let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? TimeInterval(Settings.skipBackTime)
                    if Int(interval) == Settings.skipBackTime {
                        self.analyticsPlaybackHelper.currentSource = self.commandCenterSource
                        self.handleRemoteAction(.previousEpisode)

                        return .success
                    }
                }

                self.analyticsPlaybackHelper.currentSource = self.commandCenterSource

                if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
                    self.skipBack(amount: skipEvent.interval)
                } else {
                    self.skipBack()
                }

                return .success
            }
        } else {
            setInterval(commandCenter.skipBackwardCommand, interval: skipBackAmount, handler: nil)
        }

        let skipFwdAmount = TimeInterval(Settings.skipForwardTime)
        if addTarget {
            setInterval(commandCenter.skipForwardCommand, interval: skipFwdAmount) { event -> MPRemoteCommandHandlerStatus in
                let skipChapters = Settings.headphonesNextAction == .nextChapter

                // if the user has remote chapter skipping on, try to honour that setting if there's no interval that comes through, or the interval matches the default one
                if skipChapters, let nextChapter = self.chapterManager.nextVisiblePlayableChapter() {
                    let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? TimeInterval(Settings.skipForwardTime)
                    if Int(interval) == Settings.skipForwardTime {
                        FileLog.shared.addMessage("Skipping to next chapter because Remote Skip Chapters is turned on")
                        self.seekTo(time: ceil(nextChapter.startTime.seconds))

                        return .success
                    }
                }

                // same hijack for the next-episode headphone action; a mismatched
                // interval is a Siri custom skip and passes through to a plain skip
                if Settings.headphonesNextAction == .nextEpisode {
                    let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? TimeInterval(Settings.skipForwardTime)
                    if Int(interval) == Settings.skipForwardTime {
                        self.analyticsPlaybackHelper.currentSource = self.commandCenterSource
                        self.handleRemoteAction(.nextEpisode)

                        return .success
                    }
                }

                self.analyticsPlaybackHelper.currentSource = self.commandCenterSource

                if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
                    self.skipForward(amount: skipEvent.interval)
                } else {
                    self.skipForward()
                }

                return .success
            }
        } else {
            setInterval(commandCenter.skipForwardCommand, interval: skipFwdAmount, handler: nil)
        }
    }

    private func setInterval(_ command: MPSkipIntervalCommand, interval: TimeInterval, handler: ((MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)?) {
        var intervalAmount = interval
        if intervalAmount > 99 { intervalAmount = 99 }
        command.isEnabled = true
        command.preferredIntervals = [NSNumber(value: intervalAmount)]

        if let handler {
            command.addTarget(handler: handler)
        }
    }

    // MARK: - AVAudioSession Notifications

    private func handleRouteChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo, let changeReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? NSNumber else { return }

        logRouteChange(userInfo: userInfo)

        let reason = changeReason.uintValue
        if let currEpisode = currentEpisode(), playingOverAirplay() && playerSwitchRequired() {
            // Never autoplay on an AirPlay player switch unless we were already playing
            // (previously gated by the retired dontAutoplayOnRouteChange flag)
            let wasPlaying = player?.shouldBePlaying() ?? false
            if wasPlaying {
                FileLog.shared.addMessage("PlaybackManager: Route change with active playback, preserving autoPlay=true")
            }
            load(episode: currEpisode, autoPlay: wasPlaying, overrideUpNext: false)
        } else if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
            // Route rules: pause only if the disconnecting route's rule says so (default: pause)
            let disconnectedPort = (userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?.outputs.first
            let rule = disconnectedPort.map { RouteRulesStore.shared.rule(for: RouteRulesStore.identity(portType: $0.portType.rawValue, portName: $0.portName)) } ?? RouteRule()
            let action = RouteChangeDecider.action(for: .disconnect, rule: rule, isPlaying: playing(), hasCurrentEpisode: currentEpisode() != nil)
            if action != .pause {
                FileLog.shared.addMessage("PlaybackManager: not pausing on disconnect of \(disconnectedPort?.portName ?? "unknown route") per route rule")
            }
            player?.routeDidChange(shouldPause: action == .pause)
        } else if reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue || reason == AVAudioSession.RouteChangeReason.override.rawValue || reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue {
            player?.routeDidChange(shouldPause: false)
            updateAllNowPlayingData()

            // Route rules: optionally auto-resume when a configured route connects
            if reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
               let newPort = AVAudioSession.sharedInstance().currentRoute.outputs.first {
                let rule = RouteRulesStore.shared.rule(for: RouteRulesStore.identity(portType: newPort.portType.rawValue, portName: newPort.portName))
                if RouteChangeDecider.action(for: .connect, rule: rule, isPlaying: playing(), hasCurrentEpisode: currentEpisode() != nil) == .resume {
                    FileLog.shared.addMessage("PlaybackManager: auto-resuming for connect of \(newPort.portName) per route rule")
                    play(userInitiated: false)
                }
            }
        }
    }

    private func logRouteChange(userInfo: [AnyHashable: Any]) {
        guard let changeReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? NSNumber,
              let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
              let currentRoute = AVAudioSession.sharedInstance().currentRoute as AVAudioSessionRouteDescription? else {
            return
        }

        let previousOutputDescriptions = previousRoute.outputs.map { $0.portName }.joined(separator: ", ")
        let currentOutputDescriptions = currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        if let reason = AVAudioSession.RouteChangeReason(rawValue: UInt(changeReason.intValue)) {
            FileLog.shared.addMessage("PlaybackManager: Handle route change \(reason) | Previous Outputs: [\(previousOutputDescriptions)] | Current Outputs: [\(currentOutputDescriptions)]")
        }

        // Both sides of the change go into the recently-seen routes list so a just-disconnected
        // device can still be configured in Settings → Devices. Built-in outputs are skipped:
        // they never connect/disconnect, so rules for them can't apply.
        let builtInPorts: Set<AVAudioSession.Port> = [.builtInSpeaker, .builtInReceiver]
        for output in previousRoute.outputs + currentRoute.outputs where !builtInPorts.contains(output.portType) {
            RouteRulesStore.shared.noteSeen(
                identity: RouteRulesStore.identity(portType: output.portType.rawValue, portName: output.portName),
                displayName: output.portName)
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let interruptionType = userInfo[AVAudioSessionInterruptionTypeKey] as! NSNumber
        let interruptionReason = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt
        if interruptionType.uintValue == AVAudioSession.InterruptionType.ended.rawValue {
            interruptInProgress = false
            let interruptionOption = userInfo[AVAudioSessionInterruptionOptionKey] as! NSNumber
            FileLog.shared.addMessage("PlaybackManager handleAudioInterrupt ended, should attempt to restart audio: \(interruptionOption) reason: \(interruptionReason?.description ?? "unknown")")
            if interruptionOption.uintValue == AVAudioSession.InterruptionOptions.shouldResume.rawValue, wasPlayingBeforeInterruption {
                play(userInitiated: false)
                wasPlayingBeforeInterruption = false
            }
        } else if interruptionType.uintValue == AVAudioSession.InterruptionType.began.rawValue {
            // See https://github.com/Automattic/pocket-casts-ios/issues/2049
            // Since iOS 17, we receive an interruption when audio routes are disconnected.
            // Previous app logic relied on the fact that InterruptionType.began would always be followed by a
            // subsequent InterruptionType.ended notification, to set interruptInProgress correctly.
            // When routes are disconnected, there is no associated end event though. If the route reconnects, we'll
            // receive a different notification which is already handled elsewhere.
            if interruptionReason != AVAudioSession.InterruptionReason.routeDisconnected.rawValue {
                interruptInProgress = true
            }

            FileLog.shared.addMessage("PlaybackManager handleAudioInterrupt began reason: \(interruptionReason?.description ?? "unknown")")
            if let player {
                wasPlayingBeforeInterruption = player.shouldBePlaying()
                player.interruptionDidStart()
            }

            if let episode = currentEpisode() {
                catchUpHelper.playbackDidPause(of: episode, playedUpTo: positionTracker.playedUpTo(for: episode))
            }
            NotificationCenter.postOnMainThread(PlaybackPaused())
        }
    }

    private func handleSystemAudioReset(_: Notification) {
        if currentEpisode() != nil {
            cleanupCurrentPlayer(permanent: false)
        }
    }

    // MARK: - Background Handling

    private func startBackgroundTask() {
        if backgroundTask != UIBackgroundTaskIdentifier.invalid { return } // already started

        // Playback calls this from its own queues; bridge the UIKit call
        let begin: @Sendable () -> UIBackgroundTaskIdentifier = { [weak self] in
            MainActor.assumeIsolated {
                UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    self?.endBackgroundTask()
                })
            }
        }
        backgroundTask = Thread.isMainThread ? begin() : DispatchQueue.main.sync(execute: begin)
    }

    private func endBackgroundTask() {
        if backgroundTask == .invalid { return } // already cancelled

        let task = backgroundTask
        backgroundTask = UIBackgroundTaskIdentifier.invalid
        let end: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                UIApplication.shared.endBackgroundTask(task)
            }
        }
        if Thread.isMainThread { end() } else { DispatchQueue.main.sync(execute: end) }
    }

    // MARK: - Starred changed externally

    func nowPlayingStarredChanged() {
        queue.nowPlayingEpisodeChanged()
        guard let episode = currentEpisode() else { return }
        MPRemoteCommandCenter.shared().likeCommand.isActive = episode.keepEpisode
    }

    // MARK: - Downloading a streamed episode check

    private func handleEpisodeDidDownload(episodeUuid: String?) {
        guard let playingEpisode = currentEpisode(), let uuid = episodeUuid else { return }

        if uuid != playingEpisode.uuid { return } // download isn't the episode we're playing

        // the episode we have won't be marked as downloaded, so grab a fresh copy from the database
        if let refreshedEpisode = DataManager.sharedManager.findBaseEpisode(uuid: uuid) {
            // the current episode we were playing has downloaded, switch to playing the downloaded version
            let currentlyPlaying = playing()
            recordPlaybackPosition(sendToServerImmediately: false, fireNotifications: true)

            if !needsToReloadPlayingEpisode(refreshedEpisode) {
                return
            }

            load(episode: refreshedEpisode, autoPlay: currentlyPlaying, overrideUpNext: false, saveCurrentEpisode: false)
            if refreshedEpisode.videoPodcast() {
                NotificationCenter.postOnMainThread(VideoPlaybackEngineSwitched())
            }
        }
    }

    func needsToReloadPlayingEpisode(_ refreshedEpisode: BaseEpisode) -> Bool {
        let episodeIsChanging = refreshedEpisode.uuid != currentEpisode()?.uuid

        if !episodeIsChanging,
           effects().trimSilence == .off,
           !playerSwitchRequired(),
           !refreshedEpisode.videoPodcast() {
            return false
        } else {
            if !episodeIsChanging {
                FileLog.shared.addMessage("Playback Manager: Needs to reload current episode [\(refreshedEpisode.title ?? "") - \(refreshedEpisode.uuid)].\n Possible Reasons: Trim silence: \(effects().trimSilence), Player switch required: \(playerSwitchRequired()), Video podcast: \(refreshedEpisode.videoPodcast())")
            }
            return true
        }
    }

    private func handleEpisodeDidUpdate(episodeUuid: String?) {
        guard let playingEpisode = currentEpisode(), let uuid = episodeUuid, uuid == playingEpisode.uuid else { return }

        // update the cached copy of the now playing episode so we have the latest version of it
        queue.nowPlayingEpisodeChanged()
    }

    private func handleCurrentlyPlayingEpisodeUpdated() {
        // Update episode switch time when the currently playing episode changes
        episodeSwitchTime = Date()
    }

    // MARK: - Interruptions

    func interruptionInProgress() -> Bool {
        interruptInProgress
    }

    // MARK: - Private helpers

    private func startFromTimeForCurrentEpisode() -> TimeInterval {
        guard let episode = currentEpisode() as? Episode, let parentPodcast = episode.parentPodcast() else { return 0 }

        return TimeInterval(parentPodcast.autoStartFrom)
    }

    private func skipLastTimeForCurrentEpisode() -> TimeInterval {
        guard let episode = currentEpisode() as? Episode, let parentPodcast = episode.parentPodcast() else { return 0 }

        return TimeInterval(parentPodcast.autoSkipLast)
    }

    // MARK: - Keep Screen on

    func updateIdleTimer() {
            DispatchQueue.main.async {
                if self.playing() {
                    let keepScreenOn: Bool
                    if FeatureFlag.newSettingsStorage.enabled {
                        keepScreenOn = SettingsStore.appSettings.keepScreenAwake
                    } else {
                        keepScreenOn = UserDefaults.standard.bool(forKey: Constants.UserDefaults.keepScreenOnWhilePlaying)
                    }
                    UIApplication.shared.isIdleTimerDisabled = keepScreenOn
                } else {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
    }

    // MARK: - Autoplay

    /// Autoplay the next episode
    private func autoplayIfNeeded() {
        #if !APPCLIP
        // If Autoplay is enabled we check if there's another episode to play
        if Settings.autoplay,
           queue.upNextCount() == 0,
           let episode = currentEpisode() {

            if let nextEpisode = AutoplayHelper.shared.nextEpisode(currentEpisodeUuid: episode.uuid) {
                FileLog.shared.addMessage("Autoplaying next episode: \(nextEpisode.displayableTitle())")
                queue.add(episode: nextEpisode, fireNotification: false)
                Analytics.track(.playbackEpisodeAutoplayed, properties: ["episode_uuid": nextEpisode.uuid])
                return
            } else {
                Analytics.track(.autoplayFinishedLastEpisode)
            }
        }

        // Nothing to autoplay or Up Next has items, reset the latest played from
        AutoplayHelper.shared.playedFrom(playlist: nil)
        #endif
    }

    // MARK: - Episode Update (Playback Failure)

    // If we're streaming an episode and it fails, try to make sure the URL is up to date.
    // Authors can change URLs at any time, so this is handy to fix cases where they post
    // the wrong one and update it later
    // This method returns false if no retry is done, because we already did it before.
    func retryUrlLoad(for episodeUuid: String) -> Bool {

        guard lastRetryEpisodeUuid != episodeUuid,
              let episode = DataManager.sharedManager.findEpisode(uuid: episodeUuid),
              let podcast = episode.parentPodcast() else {
            lastRetryEpisodeUuid = episodeUuid
            return false
        }
        Task {
            haveCalledPlayerLoad = false
            FileLog.shared.addMessage("PlaybackManager: URL failed to load, trying to update episode and playing again")
            lastRetryEpisodeUuid = episodeUuid

            ServerPodcastManager.shared.updatePodcastIfRequired(podcast: podcast) { [weak self] wasUpdated in
                guard let self,
                      let updatedEpisode = wasUpdated ? DataManager.sharedManager.findEpisode(uuid: episodeUuid) : episode else { return }

                FileLog.shared.addMessage("PlaybackManager: Episode\(wasUpdated ? " " : " not") updated, trying to play again.")

                Task { @MainActor in
                    self.load(episode: updatedEpisode, autoPlay: true, overrideUpNext: false)
                }
            }
        }
        return true
    }

    // MARK: - Analytics

    private let commandCenterSource: AnalyticsSource = .nowPlayingWidget


    // MARK: - tvOS

    var avPlayer: AVPlayer? {
        guard let defaultPlayer = player as? DefaultPlayer else {
            return nil
        }

        return defaultPlayer.player
    }
}

private extension PlaybackManager {
    func handleRemoteAction(_ action: HeadphoneControlAction) {
        switch action {
        case .addBookmark:
            #if !APPCLIP
            bookmark(source: .headphones)
            #endif

        case .previousChapter:
            guard let chapter = chapterManager.previousVisibleChapter() else { fallthrough }
            FileLog.shared.addMessage("Skipping to previous chapter because Remote Skip Chapters is turned on")
            seekTo(time: ceil(chapter.startTime.seconds))

        case .skipBack:
            skipFromRemote(isBack: true)

        case .nextChapter:
            guard let chapter = chapterManager.nextVisiblePlayableChapter() else { fallthrough }
            FileLog.shared.addMessage("Skipping to next chapter because Remote Skip Chapters is turned on")
            seekTo(time: ceil(chapter.startTime.seconds))

        case .skipForward:
            skipFromRemote(isBack: false)

        case .nextEpisode:
            guard debounceRemoteEpisodeSkip("nextTrackCommand") else { return }
            skipToNextEpisode()

        case .previousEpisode:
            guard debounceRemoteEpisodeSkip("previousTrackCommand") else { return }
            skipToPreviousEpisodeOrRestart()
        }
    }

    func skipFromRemote(isBack: Bool) {
        guard debounceRemoteEpisodeSkip(isBack ? "previousTrackCommand" : "nextTrackCommand") else { return }

        isBack ? skipBack() : skipForward()
    }

    /// Some headphones deliver duplicate next/previous-track events in quick succession;
    /// drop repeats inside the remote-skip debounce window so one tap never acts twice.
    func debounceRemoteEpisodeSkip(_ command: String) -> Bool {
        guard fabs(lastSeekTime.timeIntervalSinceNow) > Constants.Limits.minTimeBetweenRemoteSkips else {
            FileLog.shared.addMessage("Remote control: \(command) ignored, too soon since previous command")
            return false
        }

        lastSeekTime = Date()
        return true
    }
}

extension PlaybackManager {
    // MARK: - Analytics

    private func trackChapterSkipped() {
        var properties = chapterManager.chaptersAnalyticsProperties
        if let skippedIndex = currentChapters().visibleChapter?.index {
            // Whether the chapter being skipped was deselected by a podcast smart-skip title rule
            // rather than manually by the user
            properties["skipped_by_rule"] = chapterManager.isRuleSkipped(chapterIndex: skippedIndex)
        }
        analyticsPlaybackHelper.chapterSkipped(properties: properties)
    }

    func trackChapterEvent(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        var baseProperties = chapterManager.chaptersAnalyticsProperties
        if let extraProperties = properties {
            baseProperties = baseProperties.merging(extraProperties, uniquingKeysWith: { current, _ in return current})
        }
        analyticsPlaybackHelper.track(event, properties: baseProperties)
    }
}

// MARK: - Bookmarks

#if !APPCLIP

extension PlaybackManager {
    private var bookmarksEnabled: Bool {
        true
    }

    func bookmark(source: BookmarkAnalyticsSource) {
        guard bookmarksEnabled, let episode = currentEpisode() else {
            return
        }

        let currentTime = currentTime()
        bookmarkManager.add(to: episode, at: currentTime)

        playBookmarkCreationSoundIfNeeded(source: source)

        Analytics.track(.bookmarkCreated, source: source, properties: [
            "episode_uuid": episode.uuid,
            "podcast_uuid": (episode as? Episode)?.podcastUuid ?? "user_file",
            "time": Int(currentTime)
        ])
    }

    /// Plays the bookmark creation sound only if:
    /// - The source is from the headphones
    /// - The user has the addBookmark option enabled in the Headphone Controls setting
    /// - The bookmark sound setting is enabled
    private func playBookmarkCreationSoundIfNeeded(source: BookmarkAnalyticsSource) {
        guard source == .headphones, Settings.shouldPlayBookmarkSound else {
            return
        }

        bookmarkManager.playTone()
    }

    /// Plays the given bookmark
    /// - if the episode is not currently playing we'll load it and then play at the bookmark time
    /// - if the episode is playing, we trigger a seek to the bookmark time
    func playBookmark(_ bookmark: Bookmark, source: BookmarkAnalyticsSource, firstTry: Bool = true) {
        guard bookmarksEnabled else { return }

        // Make sure the bookmark's episode exists before tracking/seeking; fetch it once if it doesn't
        guard (bookmark.episode ?? DataManager.sharedManager.findBaseEpisode(uuid: bookmark.episodeUuid)) != nil else {
            if firstTry, let podcastUuid = bookmark.podcastUuid {
                ServerPodcastManager.shared.addMissingPodcastAndEpisode(episodeUuid: bookmark.episodeUuid, podcastUuid: podcastUuid) { [weak self] episode in
                    if episode != nil {
                        self?.playBookmark(bookmark, source: source, firstTry: false)
                    }
                }
            }
            return
        }

        Analytics.track(.bookmarkPlayTapped, source: source)

        analyticsPlaybackHelper.currentSource = .bookmark

        play(episodeUuid: bookmark.episodeUuid, podcastUuid: bookmark.podcastUuid, at: bookmark.time)
    }
}

// MARK: - Deep-link seek and play

extension PlaybackManager {
    /// Canonical seek-and-play for deep links into a moment of an episode
    /// (bookmarks, summary takeaways, transcript search hits):
    /// - the now-playing episode gets a direct seek
    /// - any other local episode has its start position stamped before the
    ///   standard play pipeline loads it (which resumes from there)
    /// - a missing episode is fetched from the server once, then retried.
    func play(episodeUuid: String, podcastUuid: String?, at time: TimeInterval, firstTry: Bool = true) {
        // If we're already the now playing episode, then just seek
        if isNowPlayingEpisode(episodeUuid: episodeUuid) {
            seekTo(time: time, startPlaybackAfterSeek: true)
            return
        }

        let dataManager = DataManager.sharedManager
        guard let episode = dataManager.findBaseEpisode(uuid: episodeUuid) else {
            if firstTry, let podcastUuid {
                ServerPodcastManager.shared.addMissingPodcastAndEpisode(episodeUuid: episodeUuid, podcastUuid: podcastUuid) { [weak self] episode in
                    if episode != nil {
                        self?.play(episodeUuid: episodeUuid, podcastUuid: podcastUuid, at: time, firstTry: false)
                    }
                }
            }
            return
        }

        // Save the playback time before we start playing so the player will jump to the correct starting time when it does load
        dataManager.saveEpisode(playedUpTo: time, episode: episode, updateSyncFlag: false)
        dataManager.saveEpisode(playingStatus: .inProgress, episode: episode, updateSyncFlag: false)
        // Start the play process
        PlaybackActionHelper.play(episode: episode)
    }
}

// MARK: - SearchResults
extension PlaybackManager {

    func playEpisodeSearchResult(_ searchEpisode: EpisodeSearchResult, firstTry: Bool = true) {
        let dataManager = DataManager.sharedManager

        // Get the bookmark's BaseEpisode so we can load it
        guard let episode = dataManager.findBaseEpisode(uuid: searchEpisode.uuid) else {
            guard firstTry else { return }
            ServerPodcastManager.shared.addMissingPodcastAndEpisode(episodeUuid: searchEpisode.uuid, podcastUuid: searchEpisode.podcastUuid) { [weak self] episode in
                if episode != nil {
                    self?.playEpisodeSearchResult(searchEpisode, firstTry: false)
                }
            }
            return
        }

        // Start the play process
        PlaybackActionHelper.play(episode: episode)
    }
}
#endif

// MARK: - Up Next queue forwarding

/// The Up Next queue is an implementation detail of the playback subsystem
/// (Phase 5, docs/Phase5-PlaybackModernization.md D6): external callers use these
/// forwarders instead of reaching into PlaybackQueue directly.
extension PlaybackManager {
    func upNextCount() -> Int {
        queue.upNextCount()
    }

    func episodeInUpNextAt(index: Int) -> BaseEpisode? {
        queue.episodeAt(index: index)
    }

    func upNextTotalDuration(includePlayingEpisode: Bool) -> TimeInterval {
        queue.upNextTotalDuration(includePlayingEpisode: includePlayingEpisode)
    }

    func moveUpNextEpisode(_ episode: BaseEpisode, to: Int, fireNotification: Bool = true) {
        queue.move(episode: episode, to: to, fireNotification: fireNotification)
    }

    func bulkMoveUpNext(_ playlistEpisodes: [PlaylistEpisode], toTop: Bool) {
        queue.bulkMove(playlistEpisodes, toTop: toTop)
    }

    func clearUpNextList() {
        queue.clearUpNextList()
    }

    func refreshUpNextList(checkForAutoDownload: Bool) {
        queue.refreshList(checkForAutoDownload: checkForAutoDownload)
    }

    func upNextBulkOperationDidComplete() {
        queue.bulkOperationDidComplete()
    }

    func allUpNextEpisodes(includeNowPlaying: Bool = true) -> [BaseEpisode] {
        queue.allEpisodes(includeNowPlaying: includeNowPlaying)
    }

    func reorderUpNext(sortedEpisodes: [BaseEpisode]) {
        queue.reorderUpNext(sortedEpisodes: sortedEpisodes)
    }

    func moveUpNextEpisode(from: Int, to: Int) {
        queue.moveEpisode(from: from, to: to)
    }
}
