import Foundation

/// App-side capabilities the sync engine needs but the module can't own:
/// playback state (PlaybackManager), server-backed metadata backfill
/// (ServerPodcastManager), app settings (SettingsStore) and stats
/// (StatsManager). Mirrors the role ServerSyncDelegate plays for server
/// sync. All methods may be called off the main actor.
public protocol FileSyncDelegate: Sendable {
    // MARK: Playback

    /// True when this episode is loaded in the player and actively playing
    /// (local state wins over remote ops for it).
    func isEpisodeActivelyPlaying(uuid: String) -> Bool
    /// True when this episode is loaded in the player (playing or paused).
    func isEpisodeInPlayer(uuid: String) -> Bool
    /// Remote position applied to the paused in-player episode.
    func seekToFromSync(episodeUuid: String, time: Double)
    /// The current queue (now-playing first) as episode uuids.
    func currentQueueEpisodeUuids() -> [String]
    /// Reload the in-memory queue after the applier rewrote its rows.
    func refreshQueueFromDatabase()

    // MARK: Server-backed metadata backfill (best effort; may fail offline)

    /// Fetch + store a podcast (with episodes) the folder references but
    /// this device doesn't have. Returns success.
    func backfillPodcast(uuid: String) async -> Bool
    /// Fetch + store a single missing episode. Returns success.
    func backfillEpisode(uuid: String, podcastUuid: String) async -> Bool

    // MARK: Settings

    /// Current app-level settings as (name, JSON value, modified-at ms),
    /// only fields that have ever been changed by the user.
    func collectChangedSettings() -> [FileSyncSettingChange]
    /// Apply a merged remote setting if its modifiedAt is newer than local.
    func applySetting(_ change: FileSyncSettingChange)

    // MARK: Stats

    /// This device's lifetime listening counters.
    func collectStats() -> Filesync_StatsCumulative
    /// Store the sum of peer devices' counters (shown inclusively).
    func applyPeerStats(_ totals: Filesync_StatsCumulative)
}

public struct FileSyncSettingChange: Sendable, Equatable {
    public let name: String
    public let jsonValue: String
    public let modifiedAtMs: Int64

    public init(name: String, jsonValue: String, modifiedAtMs: Int64) {
        self.name = name
        self.jsonValue = jsonValue
        self.modifiedAtMs = modifiedAtMs
    }
}
