import Foundation
import Testing
@testable import PocketCastsDataModel

/// User-facing backup/restore: unlike corruption recovery (`copyAllData`), a restore
/// must bring back `SJEpisode` rows too, and must replace — not merge with — whatever
/// the destination library contains.
@Suite("Backup and restore round trip")
struct BackupRestoreRoundTripTests {
    @Test("a restored library contains the backed-up podcasts AND episodes")
    func roundTripIncludesEpisodes() throws {
        let source = DataManager.newTestDataManager()

        var podcast = Podcast()
        podcast.uuid = "podcast-1"
        podcast.title = "Backed Up"
        podcast.addedDate = Date()
        podcast.subscribed = 1
        let savedPodcast = source.save(podcast: podcast)

        var episode = Episode()
        episode.uuid = "episode-1"
        episode.title = "Backed Up Episode"
        episode.addedDate = Date()
        episode.podcastUuid = savedPodcast.uuid
        episode.podcast_id = savedPodcast.id
        episode.playedUpTo = 123
        source.save(episode: episode)

        let backupPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString).sqlite3").path
        try source.backupDatabase(to: backupPath)
        defer { try? FileManager.default.removeItem(atPath: backupPath) }

        // the destination has its own content, which restore must replace
        let destination = DataManager.newTestDataManager()
        var preexisting = Podcast()
        preexisting.uuid = "pre-existing"
        preexisting.addedDate = Date()
        preexisting.subscribed = 1
        destination.save(podcast: preexisting)

        #expect(destination.restoreAllData(fromPath: backupPath))

        #expect(destination.findPodcast(uuid: "podcast-1", includeUnsubscribed: true)?.title == "Backed Up")
        #expect(destination.findPodcast(uuid: "pre-existing", includeUnsubscribed: true) == nil)

        let restoredEpisode = destination.findEpisode(uuid: "episode-1")
        #expect(restoredEpisode?.title == "Backed Up Episode")
        #expect(restoredEpisode?.playedUpTo == 123)
    }

    @Test("restore from a missing backup fails without touching the library")
    func missingBackupFails() {
        let dataManager = DataManager.newTestDataManager()

        var podcast = Podcast()
        podcast.uuid = "kept"
        podcast.addedDate = Date()
        podcast.subscribed = 1
        dataManager.save(podcast: podcast)

        #expect(!dataManager.restoreAllData(fromPath: "/nonexistent/backup.sqlite3"))
        #expect(dataManager.findPodcast(uuid: "kept", includeUnsubscribed: true) != nil)
    }
}
