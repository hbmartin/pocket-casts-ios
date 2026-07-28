import ActivityKit
import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

/// Owns the Now Playing Live Activity lifecycle: starts it when playback starts,
/// updates on play/pause/track/chapter changes (the progress bar ticks by itself
/// via timer-interval rendering, so no periodic updates are needed), and ends it
/// when playback stops. Observes the existing playback notifications rather than
/// hooking `PlaybackManager` directly, mirroring `WidgetHelper`.
final class NowPlayingLiveActivityManager {
    static let shared = NowPlayingLiveActivityManager()

    private var activity: Activity<NowPlayingActivityAttributes>?

    /// The last state pushed, for detecting seeks: a progress tick whose actual
    /// position drifts from this state's wall-clock projection means the user
    /// jumped, and the projection needs re-anchoring.
    private var lastContentState: NowPlayingActivityAttributes.ContentState?

    /// Playback seconds of divergence between actual and projected position
    /// before a progress tick counts as a seek. Generous enough that timer
    /// jitter and rate rounding never trip it.
    nonisolated private static let seekDriftThreshold: TimeInterval = 3

    private var messageTokens = [NotificationCenter.ObservationToken]()

    func setup() {
        let center = NotificationCenter.default
        messageTokens.append(center.addObserver(for: PlaybackStarted.self) { [weak self] _ in
            self?.playbackChanged()
        })
        messageTokens.append(center.addObserver(for: PlaybackPaused.self) { [weak self] _ in
            self?.playbackChanged()
        })
        messageTokens.append(center.addObserver(for: PlaybackTrackChanged.self) { [weak self] _ in
            self?.playbackChanged()
        })
        messageTokens.append(center.addObserver(for: PodcastChapterChanged.self) { [weak self] _ in
            self?.playbackChanged()
        })
        messageTokens.append(center.addObserver(for: PlaybackEffectsChanged.self) { [weak self] _ in
            self?.playbackChanged()
        })
        messageTokens.append(center.addObserver(for: PlaybackProgressed.self) { [weak self] _ in
            self?.progressTicked()
        })
        messageTokens.append(center.addObserver(for: PlaybackEnded.self) { [weak self] _ in
            self?.playbackEnded()
        })

        // Playback may already be stopped from a previous run; reap stale activities.
        endAllActivities()
    }

    deinit {
        // Property reads must precede any nonisolated work in deinit (Swift 6.2
        // isolated-deinit rule).
        let tokens = messageTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func playbackChanged() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let episode = PlaybackManager.shared.currentEpisode() else {
            endActivity()
            return
        }

        let chapterTitle = PlaybackManager.shared.currentChapters().visibleChapter?.title
        let state = NowPlayingActivityAttributes.ContentState(
            episodeTitle: episode.displayableTitle(),
            podcastName: episode.subTitle(),
            chapterTitle: (chapterTitle?.isEmpty == false) ? chapterTitle : nil,
            isPlaying: PlaybackManager.shared.playing(),
            position: PlaybackManager.shared.currentTime(),
            duration: PlaybackManager.shared.duration(),
            capturedAt: Date(),
            playbackRate: PlaybackManager.shared.effects().playbackSpeed,
            artworkFileName: publishArtwork(for: episode)
        )
        lastContentState = state

        if let activity {
            // Activity's async methods are @concurrent and the type carries no
            // Sendable annotation; it is internally thread-safe, so hand it over boxed.
            let boxed = UncheckedSendable(activity)
            Task { await boxed.value.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                activity = try Activity.request(
                    attributes: NowPlayingActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil)
                )
            } catch {
                FileLog.shared.addMessage("NowPlayingLiveActivity: failed to start: \(error)")
            }
        }
    }

    /// Seeks have no dedicated notification; they surface as a progress tick
    /// whose position no longer matches the last pushed state's wall-clock
    /// projection. Ordinary ticks stay inside the threshold, so this adds no
    /// periodic activity updates.
    private func progressTicked() {
        guard activity != nil, let lastContentState else { return }

        if Self.isSeekDrift(state: lastContentState, currentTime: PlaybackManager.shared.currentTime(), now: Date()) {
            playbackChanged()
        }
    }

    /// The pure drift decision behind `progressTicked()`, split out for tests:
    /// projects where playback should be if `state` still held (frozen while
    /// paused; advancing at `playbackRate` playback-seconds per wall second
    /// while playing) and reports whether the actual position has jumped away.
    nonisolated static func isSeekDrift(state: NowPlayingActivityAttributes.ContentState, currentTime: TimeInterval, now: Date) -> Bool {
        let projected: TimeInterval
        if state.isPlaying {
            let elapsed = now.timeIntervalSince(state.capturedAt)
            projected = state.position + elapsed * (state.playbackRate ?? 1)
        } else {
            projected = state.position
        }
        return abs(currentTime - projected) > seekDriftThreshold
    }

    private func playbackEnded() {
        endActivity()
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        lastContentState = nil
        let boxed = UncheckedSendable(activity)
        Task { await boxed.value.end(nil, dismissalPolicy: .immediate) }
    }

    /// Ends every activity of our type — used at launch to clean up leftovers
    /// from a previous process (the `activity` reference does not survive relaunch).
    private func endAllActivities() {
        // Boxed like endActivity() above: Activity is not Sendable and end(_:dismissalPolicy:)
        // is @concurrent, so each reference crosses out of the main actor via the box.
        let staleActivities = Activity<NowPlayingActivityAttributes>.activities.map { UncheckedSendable($0) }
        Task {
            for boxed in staleActivities {
                await boxed.value.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Writes the current episode's cached artwork (downscaled) into the shared
    /// app-group container so the widget process can render it. Returns the file
    /// name, or nil when no artwork is cached yet (a later update retries).
    private func publishArtwork(for episode: BaseEpisode) -> String? {
        guard let directory = NowPlayingActivityArtwork.containerURL(groupId: SharedConstants.GroupUserDefaults.groupContainerId) else { return nil }

        let image: UIImage? = if let episode = episode as? Episode {
            ImageManager.sharedManager.cachedImageFor(podcastUuid: episode.parentIdentifier(), size: .list)
        } else if let userEpisode = episode as? UserEpisode {
            ImageManager.sharedManager.cachedImageForUserEpisode(episode: userEpisode, size: .list)
        } else {
            nil
        }
        guard let image else { return nil }

        let fileName = "artwork-\(episode.uuid).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileName
        }

        // Encode only on the write path; a failed encode must not report a file that was never written.
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Fresh episode: clear predecessors so the group container holds at most one file.
            if let existing = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
                for name in existing {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            try imageData.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            FileLog.shared.addMessage("NowPlayingLiveActivity: failed to publish artwork: \(error)")
            return nil
        }
    }
}
