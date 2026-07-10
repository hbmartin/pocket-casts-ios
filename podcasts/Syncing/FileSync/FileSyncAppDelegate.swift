import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsServer
import PocketCastsUtils

/// App-side implementation of the local file-sync capability bridge.
///
/// The sync module owns folder I/O and merge rules; this type connects the
/// merged result back to app services the module cannot depend on directly:
/// playback, best-effort feed backfill, settings, and listening stats.
nonisolated final class FileSyncAppDelegate: FileSyncDelegate, Sendable {
    private func onMain<T>(_ body: @MainActor (PlaybackManager) -> T) -> T {
        PlaybackManager.onMainSync(body)
    }

    func isEpisodeActivelyPlaying(uuid: String) -> Bool {
        onMain { $0.isActivelyPlaying(episodeUuid: uuid) }
    }

    func isEpisodeInPlayer(uuid: String) -> Bool {
        onMain { $0.isNowPlayingEpisode(episodeUuid: uuid) }
    }

    func seekToFromSync(episodeUuid: String, time: Double) {
        onMain { playbackManager in
            guard playbackManager.isNowPlayingEpisode(episodeUuid: episodeUuid),
                  !playbackManager.playing() else { return }
            playbackManager.seekToFromSync(time: time, syncChanges: false, startPlaybackAfterSeek: false)
        }
    }

    func currentQueueEpisodeUuids() -> [String] {
        onMain { $0.allEpisodesInQueue(includeNowPlaying: true).map(\.uuid) }
    }

    func refreshQueueFromDatabase() {
        onMain { $0.queueRefreshList(checkForAutoDownload: true) }
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.upNextQueueChanged)
    }

    func backfillPodcast(uuid: String, feedURL: String?) async -> Bool {
        // A uuid that is the deterministic hash of the record's feed URL is a local-feed
        // podcast: the Pocket Casts servers have never heard of it, so re-ingest it from
        // the feed itself — this is how local podcasts propagate across devices.
        if let feedURL, LocalFeedIdentity.uuid(seed: feedURL) == uuid {
            return await withCheckedContinuation { continuation in
                ServerPodcastManager.shared.addLocalFeed(feedURL: feedURL, subscribe: true) { added in
                    continuation.resume(returning: added)
                }
            }
        }

        return await withCheckedContinuation { continuation in
            ServerPodcastManager.shared.addFromUuid(podcastUuid: uuid, subscribe: true) { added in
                continuation.resume(returning: added)
            }
        }
    }

    func backfillEpisode(uuid: String, podcastUuid: String) async -> Bool {
        ServerPodcastManager.shared.addMissingEpisode(episodeUuid: uuid, podcastUuid: podcastUuid) != nil
    }

    func collectChangedSettings() -> [FileSyncSettingChange] {
        []
    }

    func applySetting(_ change: FileSyncSettingChange) {
        FileLog.shared.addMessage("FileSync: ignored setting op \(change.name); settings bridge is not enabled yet")
    }

    func collectStats() -> Filesync_StatsCumulative {
        var stats = Filesync_StatsCumulative()
        stats.timeListened = Int64(StatsManager.shared.totalListeningTime())
        stats.timeSkipping = Int64(StatsManager.shared.totalSkippedTime())
        stats.timeIntroSkipping = Int64(StatsManager.shared.totalAutoSkippedTime())
        stats.timeVariableSpeed = Int64(StatsManager.shared.timeSavedVariableSpeed())
        stats.timeSilenceRemoval = Int64(StatsManager.shared.timeSavedDynamicSpeed())
        return stats
    }

    func applyPeerStats(_ totals: Filesync_StatsCumulative) {
        let defaults = UserDefaults.standard
        defaults.set(TimeInterval(totals.timeListened), forKey: "StatsListenedToServer")
        defaults.set(TimeInterval(totals.timeSkipping), forKey: "StatsSkippedServer")
        defaults.set(TimeInterval(totals.timeIntroSkipping), forKey: "StatsIntroSkipServer")
        defaults.set(TimeInterval(totals.timeVariableSpeed), forKey: "StatsVariableSpeedServer")
        defaults.set(TimeInterval(totals.timeSilenceRemoval), forKey: "StatsDynamicSpeedServer")
    }
}
