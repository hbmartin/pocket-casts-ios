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

    func setup() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(playbackChanged), name: Constants.Notifications.playbackStarted, object: nil)
        center.addObserver(self, selector: #selector(playbackChanged), name: Constants.Notifications.playbackPaused, object: nil)
        center.addObserver(self, selector: #selector(playbackChanged), name: Constants.Notifications.playbackTrackChanged, object: nil)
        center.addObserver(self, selector: #selector(playbackChanged), name: Constants.Notifications.podcastChapterChanged, object: nil)
        center.addObserver(self, selector: #selector(playbackEnded), name: Constants.Notifications.playbackEnded, object: nil)

        // Playback may already be stopped from a previous run; reap stale activities.
        endAllActivities()
    }

    @objc private func playbackChanged() {
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
            artworkFileName: publishArtwork(for: episode)
        )

        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
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

    @objc private func playbackEnded() {
        endActivity()
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Ends every activity of our type — used at launch to clean up leftovers
    /// from a previous process (the `activity` reference does not survive relaunch).
    private func endAllActivities() {
        Task {
            for activity in Activity<NowPlayingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
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

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Fresh episode: clear predecessors so the group container holds at most one file.
            if let existing = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
                for name in existing {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            try image.jpegData(compressionQuality: 0.8)?.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            FileLog.shared.addMessage("NowPlayingLiveActivity: failed to publish artwork: \(error)")
            return nil
        }
    }
}
