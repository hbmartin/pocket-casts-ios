import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// The Highlights Tour supervisor (S9): executes the pure `TourStateMachine`'s
/// effects against the real player and synthesizer.
///
/// Timing model: while a stop plays, segment-end detection rides
/// `PlaybackManager.progressTimerFired`'s 1 Hz tick (which keeps running in the
/// background); while a bridge speaks, the tick is stopped (playback is
/// paused), so transitions are driven by `SpeechAnnouncer`'s settle. Each
/// pause→speak→seek→resume bridge runs inside a background task so iOS keeps
/// the app alive with the screen off.
@MainActor
final class HighlightsTourController {
    private let episode: BaseEpisode
    private let length: TourLength
    private unowned let playbackManager: PlaybackManager

    private var machine: TourStateMachine?
    private var prepareTask: Task<Void, Never>?
    private let announcer = SpeechAnnouncer()

    /// The seek this controller just issued; `observeSeek` consumes a match
    /// (±epsilon), and any other seek becomes an `externalSeek` event.
    private var pendingSeekTarget: TimeInterval?

    /// Set while a bridge sequence runs so the pause it triggers isn't read
    /// back as a user pause.
    private var isBridging = false

    /// Reference→playback mapping applies only for reference-timeline
    /// transcripts while the fingerprint alignment happens to be active — the
    /// tour NEVER starts fingerprinting itself (jump-restarts + the
    /// background-suppressed progress notification make it useless here).
    private var transcriptSource = ""

    /// Captured at plan-ready so the whole tour runs against one immutable
    /// time mapping. Singleton restarts, stops, and episode changes must not
    /// shift later ticks back to raw transcript time.
    private var timeMapping: FingerprintTimingManager.TimeMappingSnapshot?

    private var cancellables = Set<AnyCancellable>()
    private let observationTokens = ObservationTokenBox()

    init(episode: BaseEpisode, length: TourLength, playbackManager: PlaybackManager) {
        self.episode = episode
        self.length = length
        self.playbackManager = playbackManager

        let pauseToken = NotificationCenter.default.addObserver(for: PlaybackPaused.self) { [weak self] _ in
            guard let self, !self.isBridging else { return }
            self.dispatch(.userPaused)
        }
        let playToken = NotificationCenter.default.addObserver(for: PlaybackStarted.self) { [weak self] _ in
            guard let self, !self.isBridging else { return }
            if case .suspended = self.machine?.state {
                self.dispatch(.userResumed)
            }
        }
        let trackToken = NotificationCenter.default.addObserver(for: PlaybackTrackChanged.self) { [weak self] _ in
            self?.episodeDidChange()
        }
        observationTokens.tokens = [pauseToken, playToken, trackToken]
    }

    // MARK: - Public surface

    var isActive: Bool { machine?.isActive ?? (prepareTask != nil) }

    var state: TourStateMachine.State { machine?.state ?? .preparing }

    var plan: TourPlan? { machine?.plan }

    var currentStopIndex: Int? { machine?.currentStopIndex }

    func start() {
        Analytics.track(.highlightsTourStarted, properties: [
            "episode_uuid": episode.uuid,
            "length": length.rawValue
        ])
        prepareTask = Task { [weak self] in
            await self?.prepare()
            self?.prepareTask = nil
        }
    }

    func cancel(reason: TourStateMachine.CancelReason) {
        prepareTask?.cancel()
        if isActive {
            Analytics.track(.highlightsTourCancelled, properties: ["episode_uuid": episode.uuid])
        }
        if machine == nil {
            machine = TourStateMachine(
                plan: TourPlan(stops: [], introLine: "", outroLine: ""),
                spokenTransitions: false
            )
        }
        dispatch(.cancelRequested(reason: reason))
    }

    /// Called from `progressTimerFired` (1 Hz, runs while backgrounded).
    /// Ticks are dropped while a seek is landing: on a slow (streaming) seek
    /// the player still reports the pre-seek position, which the reducer would
    /// misread as a user jump. Times are mapped into the plan's own timeline.
    func playbackTicked(time: TimeInterval, rate: Double) {
        guard pendingSeekTarget == nil, !playbackManager.isSeeking() else { return }
        dispatch(.tick(time: resolvedReferenceTime(time), rate: rate))
    }

    /// Called from `seekTo` for EVERY seek; matches our own pending jumps.
    func observeSeek(to time: TimeInterval) {
        if let pendingSeekTarget, abs(pendingSeekTarget - time) < 1 {
            self.pendingSeekTarget = nil
            return
        }
        dispatch(.externalSeek(time: resolvedReferenceTime(time)))
    }

    // MARK: - Preparation

    private func prepare() async {
        let episodeUuid = episode.uuid
        let podcastUuid = (episode as? Episode)?.podcastUuid
        let duration = episode.duration

        let transcriptManager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid ?? "")
        guard let model = try? await transcriptManager.loadTranscript(), !model.cues.isEmpty else {
            guard !Task.isCancelled else { return }
            dispatchPrepareFailure()
            return
        }
        guard !Task.isCancelled else { return }
        transcriptSource = transcriptManager.isDisplayingLocalTranscription ? "generated" : "provided"

        let cues = SummaryTakeawayGenerator.timedCues(from: model)
        let generator = SalientSegmentGenerator()
        let segments = await generator.segments(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            transcriptSource: transcriptSource,
            cues: cues,
            duration: duration
        )
        guard !Task.isCancelled else { return }

        guard let plan = TourPlanner.plan(
            segments: segments,
            length: length,
            episodeDuration: duration,
            episodeTitle: episode.displayableTitle()
        ) else {
            dispatchPrepareFailure()
            return
        }

        if case .active = FingerprintTimingManager.shared.state, transcriptSource == "provided" {
            timeMapping = FingerprintTimingManager.shared.mappingSnapshot(episodeUuid: episode.uuid)
        } else {
            timeMapping = nil
        }
        machine = TourStateMachine(plan: plan, spokenTransitions: Settings.tourSpokenTransitionsEnabled)
        dispatch(.planReady)
    }

    private func episodeDidChange() {
        prepareTask?.cancel()
        if machine == nil {
            machine = TourStateMachine(
                plan: TourPlan(stops: [], introLine: "", outroLine: ""),
                spokenTransitions: false
            )
        }
        dispatch(.episodeChanged)
    }

    private func dispatchPrepareFailure() {
        // No machine yet: synthesize the failed state directly so the picker
        // sheet can show the error.
        machine = TourStateMachine(plan: TourPlan(stops: [], introLine: "", outroLine: ""), spokenTransitions: false)
        dispatch(.planFailed)
    }

    // MARK: - Effect execution

    private func dispatch(_ event: TourStateMachine.Event) {
        guard machine != nil else { return }
        let effects = machine!.handle(event)
        guard !effects.isEmpty else { return }
        execute(effects)
    }

    private func execute(_ effects: [TourStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .pauseKeepingSession:
                isBridging = true
                playbackManager.pause(userInitiated: false, deactivateSession: false)

            case .seek(let referenceTime, let startPlayback):
                let target = resolvedSeekTime(referenceTime)
                pendingSeekTarget = target
                isBridging = false
                playbackManager.seekTo(time: target, startPlaybackAfterSeek: startPlayback)
                if startPlayback, !playbackManager.playing() {
                    playbackManager.play(userInitiated: false)
                }

            case .speakIntro:
                speak(machine?.plan.introLine ?? "")

            case .speakBridge(let nextIndex):
                speak(machine?.plan.stops[safe: nextIndex]?.bridgeLine ?? "")

            case .speakOutro:
                speak(machine?.plan.outroLine ?? "")

            case .stopSpeech:
                isBridging = false
                announcer.stop()

            case .playEarcon:
                playbackManager.bookmarkManager.playTone()

            case .pauseAtEnd:
                isBridging = false
                playbackManager.pause(userInitiated: false)

            case .notifyStateChanged:
                NotificationCenter.postOnMainThread(HighlightsTourStateChanged())

            case .notifyFinished:
                Analytics.track(.highlightsTourCompleted, properties: ["episode_uuid": episode.uuid])
                NotificationCenter.postOnMainThread(HighlightsTourFinished())
            }
        }
    }

    /// Speaks one line inside a background task; the settle drives the next
    /// transition. Speech failure degrades to `.speechUnavailable` (earcon path).
    private func speak(_ line: String) {
        guard !line.isEmpty else {
            dispatch(.speechUnavailable)
            return
        }
        playbackManager.startBackgroundTask()
        Task { [weak self] in
            let outcome = await self?.announcer.speak(line)
            self?.playbackManager.endBackgroundTask()
            switch outcome {
            case .finished:
                self?.dispatch(.speechFinished)
            case .unavailable:
                self?.dispatch(.speechUnavailable)
            case .interrupted:
                // Either our own .stopSpeech settled it (the machine has moved
                // on — the reducer ignores this) or the OS killed the utterance
                // (call/Siri): suspend so a resume can pick the tour back up
                // instead of wedging in the speech state with ticks stopped.
                self?.dispatch(.speechInterrupted)
            case nil:
                break
            }
        }
    }

    /// `TranscriptHitPlayback.resolvedSeekTime` semantics: map only when the
    /// transcript is on the reference timeline AND the fingerprint alignment
    /// was already active at plan-ready (the transcript view running
    /// alongside); raw time otherwise — ad drift accepted for v1.
    private func resolvedSeekTime(_ referenceTime: TimeInterval) -> TimeInterval {
        guard let mapped = timeMapping?.playbackTime(forReferenceTime: referenceTime) else {
            return referenceTime
        }
        return mapped
    }

    /// Inverse of `resolvedSeekTime`: the plan's stop bounds live on the
    /// transcript's reference timeline, so player times (ticks, external
    /// seeks) map back before the reducer compares them.
    private func resolvedReferenceTime(_ playbackTime: TimeInterval) -> TimeInterval {
        guard let mapped = timeMapping?.referenceTime(forPlaybackTime: playbackTime) else {
            return playbackTime
        }
        return mapped
    }
}

// MARK: - Typed messages

/// Posted on every tour state transition (the HUD re-renders from it).
nonisolated struct HighlightsTourStateChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJHighlightsTourStateChanged") }

    static func makeMessage(_ notification: Notification) -> Self? { Self() }
    static func makeNotification(_ message: Self) -> Notification { Notification(name: name) }
}

/// Posted once when a tour reaches its natural end.
nonisolated struct HighlightsTourFinished: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJHighlightsTourFinished") }

    static func makeMessage(_ notification: Notification) -> Self? { Self() }
    static func makeNotification(_ message: Self) -> Notification { Notification(name: name) }
}
