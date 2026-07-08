import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsServer
import PocketCastsUtils

/// App-side implementation of the file-sync engine's capability bridge:
/// playback state via PlaybackManager, server-backed metadata backfill via
/// ServerPodcastManager, and stats via StatsManager — mirroring the role
/// ServerSyncManager plays for server sync.
final class FileSyncAppDelegate: FileSyncDelegate {
    // MARK: Playback

    func isEpisodeActivelyPlaying(uuid: String) -> Bool {
        PlaybackManager.shared.isActivelyPlaying(episodeUuid: uuid)
    }

    func isEpisodeInPlayer(uuid: String) -> Bool {
        PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: uuid)
    }

    func seekToFromSync(episodeUuid: String, time: Double) {
        guard PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: episodeUuid),
              !PlaybackManager.shared.playing() else { return }
        PlaybackManager.shared.seekToFromSync(time: time, syncChanges: false, startPlaybackAfterSeek: false)
    }

    func currentQueueEpisodeUuids() -> [String] {
        PlaybackManager.shared.allEpisodesInQueue(includeNowPlaying: true).map(\.uuid)
    }

    func refreshQueueFromDatabase() {
        PlaybackManager.shared.queueRefreshList(checkForAutoDownload: true)
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.upNextQueueChanged)
    }

    // MARK: Server-backed backfill (best effort — the app's feed metadata
    // still comes from the PC cache server by design; a stub row is the
    // applier's fallback when these fail)

    func backfillPodcast(uuid: String) async -> Bool {
        await withCheckedContinuation { continuation in
            ServerPodcastManager.shared.addFromUuid(podcastUuid: uuid, subscribe: true) { added in
                continuation.resume(returning: added)
            }
        }
    }

    func backfillEpisode(uuid: String, podcastUuid: String) async -> Bool {
        ServerPodcastManager.shared.addMissingEpisode(episodeUuid: uuid, podcastUuid: podcastUuid) != nil
    }

    // MARK: Settings
    // App-level settings ride the engine's SettingOp channel; bridging the
    // full AppSettings surface (per-field @ModifiedDate JSON) is a
    // follow-up — until then no setting ops are emitted or applied.

    func collectChangedSettings() -> [FileSyncSettingChange] {
        []
    }

    func applySetting(_ change: FileSyncSettingChange) {
        FileLog.shared.addMessage("FileSync: setting op \(change.name) ignored (settings bridge pending)")
    }

    // MARK: Stats

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
        // Same *Server keys StatsManager.loadRemoteStats fills; the
        // inclusive getters then show local + peers automatically. (The
        // key constants are internal to the Server module, so the string
        // values are mirrored here.)
        let defaults = UserDefaults.standard
        defaults.set(TimeInterval(totals.timeListened), forKey: "StatsListenedToServer")
        defaults.set(TimeInterval(totals.timeSkipping), forKey: "StatsSkippedServer")
        defaults.set(TimeInterval(totals.timeIntroSkipping), forKey: "StatsIntroSkipServer")
        defaults.set(TimeInterval(totals.timeVariableSpeed), forKey: "StatsVariableSpeedServer")
        defaults.set(TimeInterval(totals.timeSilenceRemoval), forKey: "StatsDynamicSpeedServer")
    }
}
