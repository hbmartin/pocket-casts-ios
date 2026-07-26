import Foundation
import PocketCastsDataModel

public protocol ServerSyncDelegate: Sendable {
    // functions called by Server module during sync
    func podcastUpdated(podcastUuid: String)
    func podcastAdded(podcastUuid: String)
    func checkForUnusedPodcasts()
    func applyAutoArchivingToAllPodcasts()

    func subscribedToPodcast()

    func playlistChanged()

    func episodeStarredChanged(episode: Episode)
    func archiveEpisodeExternal(episode: Episode)
    func markEpisodeAsPlayedExternal(episode: Episode)
    func deselectedChaptersChanged()
    func episodeCanBeCleanedUp(episode: Episode) -> Bool
    func autoDownloadLatestEpisodes(uuids: [String])
    func cleanupAllUnusedEpisodeBuffers()

    func performActionsAfterSync()

    // Data required from App during sync
    func isPushEnabled() -> Bool

    func defaultPodcastGrouping() -> Int32
    func defaultShowArchived() -> Bool

    func uniqueAppId() -> String
    func appVersion() -> String
    func privateUserAgent() -> String
    func minTimeBetweenProgressSaves() -> Double
    func production() -> Bool
}
