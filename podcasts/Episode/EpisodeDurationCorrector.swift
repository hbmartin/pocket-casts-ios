import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Corrects an episode's stored duration when the feed-declared value is wrong.
///
/// Feed metadata is only reconciled with reality when an episode is played
/// (`PlaybackManager.playerDidCalculateDuration`) or fully downloaded
/// (`EpisodeFileSizeUpdater`), so an episode that is merely browsed keeps a
/// wrong duration everywhere rows render it. This runs when the episode detail
/// sheet opens: downloaded files are re-measured locally, and streaming
/// episodes are probed over the network because a plausible feed value can
/// still be wrong. Rows refresh for free via the `episodeDurationChanged`
/// notification they already observe.
nonisolated enum EpisodeDurationCorrector {
    static let probeCoordinator = EpisodeDurationProbeCoordinator(cooldown: 10.minutes)

    static func correctDurationIfNeeded(for episode: BaseEpisode) {
        if episode.downloaded(pathFinder: DownloadManager.shared) {
            EpisodeFileSizeUpdater.updateEpisodeDuration(episode: episode)
            return
        }

        guard let url = remoteProbeURL(for: episode) else { return }

        let episodeUuid = episode.uuid
        let boxed = PocketCastsUtils.UncheckedSendable((episode, AVURLAsset(url: url)))
        Task {
            guard await probeCoordinator.begin(episodeUuid: episodeUuid) else { return }
            let (episode, asset) = boxed.value
            if let loaded = try? await asset.load(.duration),
               let corrected = correction(current: episode.duration, calculated: CMTimeGetSeconds(loaded)) {
                DataManager.sharedManager.saveEpisode(duration: corrected.duration, episode: episode, updateSyncFlag: corrected.syncFlag)
                NotificationCenter.postOnMainThread(EpisodeDurationChanged(uuid: episode.uuid))
            }
            await probeCoordinator.finish(episodeUuid: episodeUuid)
        }
    }

    /// A normal-looking feed duration is not proof that it is correct, so every remote
    /// HTTP(S) episode is eligible for the lazy detail-screen probe.
    static func remoteProbeURL(for episode: BaseEpisode) -> URL? {
        guard let urlString = (episode as? Episode)?.downloadUrl,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// Thresholds match `EpisodeFileSizeUpdater` / `playerDidCalculateDuration`:
    /// reject implausible measurements (<10s or >10h), skip near-identical
    /// values, and only mark for sync when the change is meaningful.
    static func correction(current: TimeInterval, calculated: TimeInterval) -> (duration: TimeInterval, syncFlag: Bool)? {
        guard calculated >= 10, calculated <= 36000 else { return nil }
        guard Int(current) != Int(calculated) else { return nil }

        return (duration: calculated, syncFlag: abs(current - calculated) >= 30)
    }
}

actor EpisodeDurationProbeCoordinator {
    private let cooldown: TimeInterval
    private var inFlight = Set<String>()
    private var lastFinishedAt = [String: Date]()

    init(cooldown: TimeInterval) {
        self.cooldown = cooldown
    }

    func begin(episodeUuid: String, now: Date = Date()) -> Bool {
        guard !inFlight.contains(episodeUuid) else { return false }
        if let lastFinishedAt = lastFinishedAt[episodeUuid], now.timeIntervalSince(lastFinishedAt) < cooldown {
            return false
        }
        inFlight.insert(episodeUuid)
        return true
    }

    func finish(episodeUuid: String, now: Date = Date()) {
        inFlight.remove(episodeUuid)
        lastFinishedAt[episodeUuid] = now
    }
}
