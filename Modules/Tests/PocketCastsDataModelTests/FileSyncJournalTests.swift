import XCTest
@testable import PocketCastsDataModel

final class FileSyncJournalTests: XCTestCase {
    private var dataManager: DataManager!

    override func setUp() {
        super.setUp()
        dataManager = DataManager.newTestDataManager()
    }

    private func makeEpisode(uuid: String = UUID().uuidString) -> Episode {
        var episode = Episode()
        episode.uuid = uuid
        episode.podcastUuid = "pod-1"
        episode.addedDate = Date()
        dataManager.save(episode: episode)
        return dataManager.findEpisode(uuid: uuid)!
    }

    // MARK: Episode hooks

    func testUserIntentEpisodeSaveJournals() {
        let episode = makeEpisode()
        let before = dataManager.unflushedFileSyncCount()

        dataManager.saveEpisode(playedUpTo: 123, episode: episode, updateSyncFlag: true)

        let entries = dataManager.unflushedFileSyncEntries(limit: 100)
        XCTAssertEqual(entries.count, before + 1)
        let entry = entries.last!
        XCTAssertEqual(entry.entity, .episode)
        XCTAssertEqual(entry.entityUuid, episode.uuid)
        XCTAssertEqual(entry.op, .upsert)
        XCTAssertEqual(entry.changedFieldNames, ["playedUpTo"])
        XCTAssertGreaterThan(entry.wallClockMs, 0)
    }

    func testNonUserIntentEpisodeSaveDoesNotJournal() {
        let episode = makeEpisode()
        let before = dataManager.unflushedFileSyncCount()

        // updateSyncFlag: false is how server/file-applied changes save.
        dataManager.saveEpisode(playedUpTo: 456, episode: episode, updateSyncFlag: false)

        XCTAssertEqual(dataManager.unflushedFileSyncCount(), before)
    }

    func testSuppressionBracketPreventsEchoLoops() {
        let episode = makeEpisode()
        let before = dataManager.unflushedFileSyncCount()

        DataManager.withFileSyncApplySuppression {
            // Even a user-intent-flagged save inside the remote applier must
            // not journal, or applied ops would echo back to the folder.
            dataManager.saveEpisode(playedUpTo: 789, episode: episode, updateSyncFlag: true)
        }

        XCTAssertEqual(dataManager.unflushedFileSyncCount(), before)
    }

    func testHeartbeatPositionSavesCoalesce() {
        let episode = makeEpisode()
        let before = dataManager.unflushedFileSyncCount()

        for position in [10.0, 20.0, 30.0, 40.0] {
            dataManager.saveEpisode(playedUpTo: position, episode: episode, updateSyncFlag: true)
        }

        XCTAssertEqual(dataManager.unflushedFileSyncCount(), before + 1,
                       "repeated position updates for one episode must collapse to a single pending op")
    }

    // MARK: Entity hooks

    func testPodcastSaveAndDeleteJournal() {
        var podcast = Podcast()
        podcast.uuid = "pod-journal-1"
        podcast.addedDate = Date()
        dataManager.save(podcast: podcast)

        var entries = dataManager.unflushedFileSyncEntries(limit: 100)
        XCTAssertTrue(entries.contains { $0.entity == .podcast && $0.entityUuid == podcast.uuid && $0.op == .upsert })

        dataManager.delete(podcast: podcast)
        entries = dataManager.unflushedFileSyncEntries(limit: 100)
        XCTAssertTrue(entries.contains { $0.entity == .podcast && $0.entityUuid == podcast.uuid && $0.op == .delete })
    }

    func testUpNextActionsJournal() {
        dataManager.saveUpNextAddToBottom(episodeUuid: "ep-a")
        dataManager.saveUpNextRemove(episodeUuid: "ep-a")
        dataManager.saveReplace(episodeList: ["ep-1", "ep-2"])

        let entries = dataManager.unflushedFileSyncEntries(limit: 100)
        XCTAssertTrue(entries.contains { $0.entity == .upNext && $0.op == .upNextPlayLast && $0.entityUuid == "ep-a" })
        XCTAssertTrue(entries.contains { $0.entity == .upNext && $0.op == .upNextRemove && $0.entityUuid == "ep-a" })
        let replace = entries.last { $0.op == .upNextReplace }
        XCTAssertNotNil(replace)
        XCTAssertEqual(replace?.fields, "[\"ep-1\",\"ep-2\"]")
    }

    // MARK: Flush lifecycle

    func testFlushLifecycleAssignsSequentialSeqs() {
        let episode = makeEpisode()
        dataManager.saveEpisode(playedUpTo: 1, episode: episode, updateSyncFlag: true)
        dataManager.saveEpisode(starred: true, episode: episode, updateSyncFlag: true)

        let pending = dataManager.unflushedFileSyncEntries(limit: 100)
        XCTAssertGreaterThanOrEqual(pending.count, 2)

        dataManager.markFileSyncEntriesFlushed(entryIDs: pending.map(\.id), startingSeq: 41)
        XCTAssertEqual(dataManager.unflushedFileSyncCount(), 0)

        // Purge everything flushed (future cutoff): table drains.
        dataManager.purgeFlushedFileSyncEntries(olderThanMs: Int64.max)
        XCTAssertTrue(dataManager.unflushedFileSyncEntries(limit: 100).isEmpty)
    }

    // MARK: Cursors

    func testCursorRoundTrip() {
        var cursor = FileSyncCursor(peerDeviceId: "peer-1")
        cursor.fileName = "log-00000003.pcsync"
        cursor.recordOffset = 512
        cursor.lastAppliedSeq = 99
        dataManager.save(fileSyncCursor: cursor)

        let loaded = dataManager.fileSyncCursor(peerDeviceId: "peer-1")
        XCTAssertEqual(loaded, cursor)

        cursor.recordOffset = 1024
        dataManager.save(fileSyncCursor: cursor)
        XCTAssertEqual(dataManager.fileSyncCursor(peerDeviceId: "peer-1")?.recordOffset, 1024,
                       "saving again must upsert, not duplicate")

        dataManager.deleteFileSyncCursor(peerDeviceId: "peer-1")
        XCTAssertNil(dataManager.fileSyncCursor(peerDeviceId: "peer-1"))
    }

    // MARK: UserEpisode folder identity

    func testUserEpisodeFolderIdentityPersists() {
        var userEpisode = UserEpisode()
        userEpisode.uuid = "ue-journal-1"
        userEpisode.addedDate = Date()
        userEpisode.title = "Chapter 1"
        userEpisode.folderRelativePath = "Uploads/Audiobooks/chapter01.mp3"
        userEpisode.groupName = "Audiobooks"
        userEpisode.identity = .provisional
        dataManager.save(episode: userEpisode)

        let byPath = dataManager.findUserEpisode(folderRelativePath: "Uploads/Audiobooks/chapter01.mp3")
        XCTAssertEqual(byPath?.uuid, "ue-journal-1")
        XCTAssertEqual(byPath?.identity, .provisional)
        XCTAssertEqual(byPath?.groupName, "Audiobooks")

        var canonical = byPath!
        canonical.contentHash = "abc123"
        canonical.identity = .canonical
        dataManager.save(episode: canonical)

        XCTAssertEqual(dataManager.findUserEpisode(contentHash: "abc123")?.uuid, "ue-journal-1")
        XCTAssertEqual(dataManager.allFolderBackedUserEpisodes().map(\.uuid), ["ue-journal-1"])
    }
}
