import Foundation

/// App-side capabilities the sync engine needs but the module cannot own:
/// playback state, server-backed metadata backfill, app settings, and
/// listening stats. Mirrors `ServerSyncDelegate`/playback delegate roles
/// for the server sync engine.
public protocol FileSyncDelegate: Sendable {
    // MARK: Playback

    func isEpisodeActivelyPlaying(uuid: String) -> Bool
    func isEpisodeInPlayer(uuid: String) -> Bool
    func seekToFromSync(episodeUuid: String, time: Double)
    func currentQueueEpisodeUuids() -> [String]
    func refreshQueueFromDatabase()

    // MARK: Server-backed metadata backfill

    func backfillPodcast(uuid: String) async -> Bool
    func backfillEpisode(uuid: String, podcastUuid: String) async -> Bool

    // MARK: Settings

    func collectChangedSettings() -> [FileSyncSettingChange]
    func applySetting(_ change: FileSyncSettingChange)

    // MARK: Stats

    func collectStats() -> Filesync_StatsCumulative
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
